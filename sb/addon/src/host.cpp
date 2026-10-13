// SB half of SBCraft, inside ReShade: every presented frame it reads Security Breach's camera straight from memory
// (addresses published by the SBCraft UE4SS mod in sb_link.txt), converts it to Minecraft's coordinates and sends it
// to the sbcraft Fabric mod; it relays SB's floors (sb_ground.txt) as barrier columns and forwards the mouse buttons,
// the wheel and the number keys to Minecraft.
//
// Coordinates: 1 Minecraft block = 1 m = 100 Unreal units.
//   Unreal (x, y, z) [cm, left-handed, z up]  ->  Minecraft (x / 100, z / 100 + yOffset, y / 100)
//   Minecraft yaw = Unreal yaw - 90, pitch = -Unreal pitch, roll = -Unreal roll.
//   Unreal's FOV is horizontal; Minecraft's is vertical.
// yOffset puts the floor under Gregory's feet at y = 64 (F8 re-levels).
//
// Keys (while SB has the focus): F7 passthrough on/off, F8 re-level, left/right/middle mouse = Minecraft's
// attack/use/pick block, wheel and 1-9 = Minecraft's hotbar.
#include "host.h"
#include "compositor.h"
#include "ws.h"
#include <windows.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <fstream>
#include <unordered_set>
#include <vector>
#include <deque>
#include <sstream>
#include <string>
#include <reshade.hpp>

using namespace reshade::api;

namespace
{
	constexpr int kPort = 25599;
	constexpr float kPi = 3.14159265358979f;

	WsClient g_ws;
	bool g_started = false;
	bool g_enabled = true;
	int g_wsGeneration = -1;
	unsigned g_frame = 0;
	std::wstring g_linkDir;

	struct Link
	{
		int gen = -1;
		uintptr_t loc = 0, rot = 0, fov = 0, pawnLoc = 0;
		float half = 0.0f;
		std::string pawn;
		bool valid = false;
	} g_link;
	DWORD g_nextLinkRead = 0;
	DWORD g_lastLinkWrite = 0;
	FILETIME g_linkTime = {};

	bool g_leveled = false;
	double g_yOffset = 0.0;
	std::unordered_set<long long> g_sent; // floor columns and wall cells already sent
	int g_groundSeq = -1;
	DWORD g_nextGroundRead = 0;
	DWORD g_nextStatus = 0;
	int g_badReads = 0;
	std::string g_flags;
	// Minecraft's solid blocks (not barriers): each becomes an invisible blocking box in SB (sb_blocks.txt)
	std::unordered_set<long long> g_blocks;
	int g_blocksSeq = 0;
	bool g_blocksDirty = false;
	DWORD g_nextBlocksWrite = 0;
	int g_teleportSeq = 0;
	// actions for the Lua mod (sb_actions.txt): "id melee", "id explode x y z radius" (Unreal cm)
	std::deque<std::string> g_actions;
	int g_actionId = 0;
	int g_clearAtSeq = -1; // after an explosion: rebuild the barriers from the first ground pass made after it

	void log(const char *fmt, ...)
	{
		char buf[1024];
		va_list args;
		va_start(args, fmt);
		vsnprintf(buf, sizeof(buf), fmt, args);
		va_end(args);
		reshade::log::message(reshade::log::level::info, buf);
	}

	template <typename T>
	bool read_mem(uintptr_t address, T *out, size_t count = 1)
	{
		if (address == 0)
			return false;
		SIZE_T got = 0;
		return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(address), out, sizeof(T) * count, &got) &&
			got == sizeof(T) * count;
	}

	bool file_time(const std::wstring &path, FILETIME &out)
	{
		WIN32_FILE_ATTRIBUTE_DATA info;
		if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info))
			return false;
		out = info.ftLastWriteTime;
		return true;
	}

	void read_link()
	{
		if (GetTickCount() < g_nextLinkRead)
			return;
		g_nextLinkRead = GetTickCount() + 500;
		const std::wstring path = g_linkDir + L"\\sb_link.txt";
		FILETIME t;
		if (!file_time(path, t))
		{
			g_link.valid = false;
			return;
		}
		if (CompareFileTime(&t, &g_linkTime) != 0)
		{
			g_linkTime = t;
			g_lastLinkWrite = GetTickCount();
		}
		else if (GetTickCount() - g_lastLinkWrite > 5000)
		{
			g_link.valid = false; // the mod stopped refreshing it (menus, loading, or no player)
			return;
		}
		std::ifstream in(path);
		if (!in)
			return;
		Link l;
		std::string key;
		while (in >> key)
		{
			if (key == "gen") in >> l.gen;
			else if (key == "loc") in >> l.loc;
			else if (key == "rot") in >> l.rot;
			else if (key == "fov") in >> l.fov;
			else if (key == "pawnloc") in >> l.pawnLoc;
			else if (key == "half") in >> l.half;
			else if (key == "pawn") in >> l.pawn;
			else { std::string rest; std::getline(in, rest); }
		}
		l.valid = l.loc != 0 && l.rot != 0 && l.fov != 0 && l.pawnLoc != 0;
		if (l.valid && l.gen != g_link.gen)
		{
			log("SBCraft: link gen %d, pawn %s", l.gen, l.pawn.c_str());
			g_leveled = false;
		}
		g_link = l;
	}

	struct HostCam
	{
		float loc[3], rot[3], fov, pawn[3];
	};

	bool read_camera(HostCam &c)
	{
		if (!g_link.valid)
			return false;
		if (!read_mem(g_link.loc, c.loc, 3) || !read_mem(g_link.rot, c.rot, 3) || !read_mem(g_link.fov, &c.fov) ||
			!read_mem(g_link.pawnLoc, c.pawn, 3))
			return false;
		for (float v : {c.loc[0], c.loc[1], c.loc[2], c.rot[0], c.rot[1], c.rot[2], c.pawn[0], c.pawn[1], c.pawn[2]})
			if (!std::isfinite(v) || std::fabs(v) > 1e7f)
				return false;
		return c.fov > 5.0f && c.fov < 170.0f;
	}

	long long block_key(int x, int y, int z)
	{
		return (long long(x & 0x3FFFFF) << 42) | (long long(y & 0xFFFFF) << 22) | long long(z & 0x3FFFFF);
	}

	void block_unkey(long long k, int &x, int &y, int &z)
	{
		auto sext = [](long long v, int bits) { const long long m = 1LL << (bits - 1); return int((v ^ m) - m); };
		x = sext((k >> 42) & 0x3FFFFF, 22);
		y = sext((k >> 22) & 0xFFFFF, 20);
		z = sext(k & 0x3FFFFF, 22);
	}

	/// The integers of a flat JSON array `"name":[1,2,3]` in m.
	std::vector<int> json_ints(const std::string &m, const char *name)
	{
		std::vector<int> out;
		const std::string key = std::string("\"") + name + "\":[";
		size_t at = m.find(key);
		if (at == std::string::npos)
			return out;
		const char *p = m.c_str() + at + key.size();
		while (*p && *p != ']')
		{
			char *end = nullptr;
			const long v = strtol(p, &end, 10);
			if (end == p)
				break;
			out.push_back(int(v));
			p = end;
			while (*p == ',' || *p == ' ')
				++p;
		}
		return out;
	}

	bool write_atomic(const std::wstring &name, const std::string &text)
	{
		const std::wstring path = g_linkDir + L"\\" + name, tmp = path + L".tmp";
		{
			std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
			if (!out)
				return false;
			out << text;
		}
		return MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
	}

	/// {"t":"blocks","set":[x,y,z,...],"clear":[...]} from Minecraft: remember them; written out a few times a second.
	void on_blocks(const std::string &m)
	{
		const std::vector<int> set = json_ints(m, "set"), clear = json_ints(m, "clear");
		for (size_t i = 0; i + 2 < set.size(); i += 3)
			g_blocks.insert(block_key(set[i], set[i + 1], set[i + 2]));
		for (size_t i = 0; i + 2 < clear.size(); i += 3)
			g_blocks.erase(block_key(clear[i], clear[i + 1], clear[i + 2]));
		g_blocksDirty = true;
	}

	/// sb_blocks.txt: "seq N", then the Unreal centre of every Minecraft block ("x y z", cm).
	void write_blocks()
	{
		if (!g_blocksDirty || !g_leveled || GetTickCount() < g_nextBlocksWrite)
			return;
		g_nextBlocksWrite = GetTickCount() + 150;
		g_blocksDirty = false;
		std::string text = "seq " + std::to_string(++g_blocksSeq) + "\n";
		char line[96];
		for (long long k : g_blocks)
		{
			int x, y, z;
			block_unkey(k, x, y, z);
			snprintf(line, sizeof(line), "%.1f %.1f %.1f\n", (x + 0.5) * 100.0, (z + 0.5) * 100.0, (y + 0.5 - g_yOffset) * 100.0);
			text += line;
		}
		write_atomic(L"sb_blocks.txt", text);
	}

	void push_action(const std::string &action)
	{
		g_actions.push_back(std::to_string(++g_actionId) + " " + action);
		while (g_actions.size() > 64)
			g_actions.pop_front();
		std::string text;
		for (const std::string &a : g_actions)
			text += a + "\n";
		write_atomic(L"sb_actions.txt", text);
	}

	/// {"t":"explosion","pos":[x,y,z],"r":radius}: SB props and walls in the blast go, animatronics are stunned.
	void on_explosion(const std::string &m)
	{
		const size_t at = m.find("\"pos\":[");
		const size_t rat = m.find("\"r\":");
		double x, y, z, r = 4.0;
		if (at == std::string::npos || sscanf(m.c_str() + at + 7, "%lf,%lf,%lf", &x, &y, &z) != 3)
			return;
		if (rat != std::string::npos)
			sscanf(m.c_str() + rat + 4, "%lf", &r);
		char a[128];
		snprintf(a, sizeof(a), "explode %.1f %.1f %.1f %.1f", x * 100.0, z * 100.0, (y - g_yOffset) * 100.0, r * 100.0);
		push_action(a);
		g_clearAtSeq = g_groundSeq + 2;
		log("SBCraft: explosion at %.1f %.1f %.1f r %.1f", x, y, z, r);
	}

	/// {"t":"pteleport","pos":[x,y,z]}: Minecraft moved Steve (an ender pearl): move Gregory there (feet, Unreal cm).
	void on_teleport(const std::string &m)
	{
		const size_t at = m.find("\"pos\":[");
		double x, y, z;
		if (at == std::string::npos || sscanf(m.c_str() + at + 7, "%lf,%lf,%lf", &x, &y, &z) != 3)
			return;
		char text[128];
		snprintf(text, sizeof(text), "seq %d\nfeet %.1f %.1f %.1f\n", ++g_teleportSeq, x * 100.0, z * 100.0, (y - g_yOffset) * 100.0);
		write_atomic(L"sb_teleport.txt", text);
		log("SBCraft: Minecraft teleported Steve to %.2f %.2f %.2f: moving Gregory", x, y, z);
	}

	void send_view_size()
	{
		int w = 0, h = 0;
		compositor::backbuffer_size(w, h);
		if (w <= 0 || h <= 0)
			return;
		// Minecraft renders at most ~1080p worth of pixels, in SB's aspect
		const double scale = std::fmin(1.0, std::sqrt(1920.0 * 1080.0 / (double(w) * h)));
		char msg[96];
		snprintf(msg, sizeof(msg), "{\"t\":\"view\",\"w\":%d,\"h\":%d}", int(w * scale), int(h * scale));
		g_ws.send(msg);
		log("SBCraft: asked Minecraft for a %dx%d window", int(w * scale), int(h * scale));
	}

	void level(const HostCam &c)
	{
		const double feet = (c.pawn[2] - g_link.half) / 100.0;
		g_yOffset = 64.0 - feet;
		g_leveled = true;
		g_sent.clear();
		g_groundSeq = -1;
		g_ws.send("{\"t\":\"clear\"}");
		g_blocks.clear();
		g_ws.send("{\"t\":\"blocksync\",\"r\":64}");
		g_blocksDirty = true;
		log("SBCraft: levelled, feet at Unreal z %.1f, yOffset %.3f", c.pawn[2] - g_link.half, g_yOffset);
	}

	void send_ground()
	{
		if (!g_leveled || GetTickCount() < g_nextGroundRead)
			return;
		g_nextGroundRead = GetTickCount() + 200;
		std::ifstream in(g_linkDir + L"\\sb_ground.txt");
		if (!in)
			return;
		std::string key;
		int seq = -1;
		in >> key >> seq;
		if (key != "seq" || seq == g_groundSeq)
			return;
		g_groundSeq = seq;
		if (g_clearAtSeq >= 0 && seq >= g_clearAtSeq)
		{
			g_clearAtSeq = -1;
			g_ws.send("{\"t\":\"clear\"}"); // blown-away walls stop blocking in Minecraft too
			g_sent.clear();
		}
		std::string line;
		std::getline(in, line);
		std::getline(in, line); // centre
		std::string columns;
		int count = 0;
		auto flush = [&] {
			if (!columns.empty())
				g_ws.send("{\"t\":\"ground\",\"c\":[" + columns + "]}");
			columns.clear();
			count = 0;
		};
		while (std::getline(in, line))
		{
			// "x y zTop": a floor column; "w x y z": a wall cell at height z (Unreal units)
			const bool wall = !line.empty() && line[0] == 'w';
			int x, y;
			float z;
			if (sscanf(line.c_str() + (wall ? 1 : 0), "%d %d %f", &x, &y, &z) != 3)
				continue;
			// Unreal cell (x, y) -> Minecraft column (x, z = y)
			int top, bottom;
			if (wall)
				top = bottom = int(std::floor(z / 100.0 + g_yOffset)); // the block containing the sample
			else
			{
				top = int(std::floor(z / 100.0 + g_yOffset + 0.5)) - 1; // the block whose top face is nearest the floor
				bottom = top - 1;
			}
			const long long k = ((long long(x) << 32) ^ (unsigned)y) * 1000003LL + top * 2 + (wall ? 1 : 0);
			if (g_sent.count(k))
				continue;
			g_sent.insert(k);
			char e[64];
			snprintf(e, sizeof(e), "%s%d,%d,%d,%d", columns.empty() ? "" : ",", x, y, bottom, top);
			columns += e;
			if (++count >= 400)
				flush();
		}
		flush();
	}

	bool sb_has_focus()
	{
		DWORD pid = 0;
		GetWindowThreadProcessId(GetForegroundWindow(), &pid);
		return pid == GetCurrentProcessId();
	}

	/// Mouse buttons and 1-9 straight from the keyboard/mouse state: Unreal reads the mouse as raw input, which
	/// ReShade's own input state doesn't see in SB. Edges only, and only while SB has the focus.
	void forward_input(effect_runtime *rt)
	{
		static bool wasDown[2] = {};
		static bool wasKey[9] = {};
		static int logged = 0;
		const bool focus = sb_has_focus();
		static const struct { int vk; const char *key; } buttons[] = {{VK_LBUTTON, "attack"}, {VK_RBUTTON, "use"}};
		for (int i = 0; i < 2; ++i)
		{
			const bool down = focus && (GetAsyncKeyState(buttons[i].vk) & 0x8000) != 0;
			if (down != wasDown[i])
			{
				wasDown[i] = down;
				char msg[64];
				snprintf(msg, sizeof(msg), "{\"t\":\"key\",\"k\":\"%s\",\"down\":%s}", buttons[i].key, down ? "true" : "false");
				g_ws.send(msg);
				if (logged++ < 10)
					log("SBCraft: %s %s", buttons[i].key, down ? "down" : "up");
			}
		}
		uint32_t mx, my;
		int16_t wheel = 0;
		rt->get_mouse_cursor_position(&mx, &my, &wheel);
		if (focus && wheel != 0)
		{
			char msg[48];
			snprintf(msg, sizeof(msg), "{\"t\":\"scroll\",\"d\":%d}", wheel > 0 ? 1 : -1);
			g_ws.send(msg);
		}
		for (int i = 0; i < 9; ++i)
		{
			const bool down = focus && (GetAsyncKeyState('1' + i) & 0x8000) != 0;
			if (down && !wasKey[i])
			{
				char msg[32];
				snprintf(msg, sizeof(msg), "{\"t\":\"slot\",\"n\":%d}", i);
				g_ws.send(msg);
			}
			wasKey[i] = down;
		}
	}
}

namespace host
{
	void start()
	{
		if (g_started)
			return;
		g_started = true;
		wchar_t buf[MAX_PATH];
		DWORD n = GetEnvironmentVariableW(L"SBCRAFT_LINK", buf, MAX_PATH);
		if (n > 0 && n < MAX_PATH)
			g_linkDir = std::wstring(buf, n);
		else
		{
			// shared with the UE4SS mod: the path in Mods\SBCraft\link_dir.txt, else Mods\SBCraft\link (next to the exe)
			GetModuleFileNameW(nullptr, buf, MAX_PATH);
			std::wstring mod(buf);
			mod = mod.substr(0, mod.find_last_of(L"\\/") + 1) + L"Mods\\SBCraft";
			std::wifstream redirect(mod + L"\\link_dir.txt");
			std::wstring line;
			if (redirect && std::getline(redirect, line))
				while (!line.empty() && iswspace(line.back()))
					line.pop_back();
			g_linkDir = line.empty() ? mod + L"\\link" : line;
		}
		CreateDirectoryW(g_linkDir.c_str(), nullptr);
		// a new session: old pearls and actions must never replay
		DeleteFileW((g_linkDir + L"\\sb_teleport.txt").c_str());
		DeleteFileW((g_linkDir + L"\\sb_actions.txt").c_str());
		std::ifstream flags(g_linkDir + L"\addon_flags.txt");
		std::string word;
		while (flags >> word)
			g_flags += " " + word + " ";
		if (!g_flags.empty())
			log("SBCraft: debug flags:%s", g_flags.c_str());
		g_ws.start("127.0.0.1", kPort);
		log("SBCraft: host started, link dir %ls, Minecraft on 127.0.0.1:%d", g_linkDir.c_str(), kPort);
	}

	bool flag(const char *name)
	{
		return g_flags.find(std::string(" ") + name + " ") != std::string::npos;
	}

	void stop()
	{
		if (g_started)
			g_ws.stop();
		g_started = false;
	}

	void frame(effect_runtime *rt)
	{
		if (!g_started)
			start();
		++g_frame;
		if (rt->is_key_pressed(VK_F7))
		{
			g_enabled = !g_enabled;
			log("SBCraft: passthrough %s", g_enabled ? "on" : "off");
		}
		read_link();
		std::string message;
		while (g_ws.poll(message))
		{
			if (message.find("\"hello\"") != std::string::npos)
				log("SBCraft: Minecraft says %s", message.c_str());
			else if (message.find("\"t\":\"blocks\"") != std::string::npos)
				on_blocks(message);
			else if (message.find("\"t\":\"pteleport\"") != std::string::npos)
				on_teleport(message);
			else if (message.find("\"t\":\"explosion\"") != std::string::npos)
				on_explosion(message);
			else if (message.find("\"t\":\"melee\"") != std::string::npos)
				push_action("melee");
		}
		if (g_ws.generation() != g_wsGeneration && g_ws.connected())
		{
			g_wsGeneration = g_ws.generation();
			g_leveled = false; // resend the ground to a (re)started Minecraft
			send_view_size();
		}

		HostCam c;
		const bool cam = read_camera(c);
		if (!cam && g_link.valid && ++g_badReads % 300 == 1)
			log("SBCraft: camera read failed at %llx", (unsigned long long)g_link.loc);
		// only in gameplay: on the splash/title/loading screens the pawn is a DefaultPawn (and UE4 may present from
		// its loading-screen thread then)
		const bool live = g_enabled && cam && g_ws.connected() && g_link.pawn != "DefaultPawn";
		compositor::set_active(live);
		if (GetTickCount() > g_nextStatus)
		{
			g_nextStatus = GetTickCount() + 10000;
			if (cam)
				log("SBCraft: frame %u ws %d link %d, camera %.0f %.0f %.0f pitch %.1f yaw %.1f roll %.1f fov %.1f, feet z %.0f",
					g_frame, g_ws.connected(), g_link.gen, c.loc[0], c.loc[1], c.loc[2], c.rot[0], c.rot[1], c.rot[2], c.fov,
					c.pawn[2] - g_link.half);
			else
				log("SBCraft: frame %u ws %d link valid %d (no camera yet)", g_frame, g_ws.connected(), g_link.valid);
		}
		if (!live)
			return;
		if (!g_leveled || rt->is_key_pressed(VK_F8))
			level(c);

		int bw = 0, bh = 0;
		compositor::backbuffer_size(bw, bh);
		const float aspect = (bw > 0 && bh > 0) ? float(bw) / float(bh) : 16.0f / 9.0f;
		const float vfov = 2.0f * std::atan(std::tan(c.fov * kPi / 360.0f) / aspect) * 180.0f / kPi;
		const double x = c.loc[0] / 100.0, y = c.loc[2] / 100.0 + g_yOffset, z = c.loc[1] / 100.0;
		const float yaw = c.rot[1] - 90.0f, pitch = -c.rot[0], roll = -c.rot[2];
		const double fx = c.pawn[0] / 100.0, fy = (c.pawn[2] - g_link.half) / 100.0 + g_yOffset, fz = c.pawn[1] / 100.0;
		char msg[320];
		snprintf(msg, sizeof(msg),
			"{\"t\":\"cam\",\"f\":%u,\"p\":[%.4f,%.4f,%.4f],\"r\":[%.3f,%.3f,%.3f],\"fov\":%.3f,\"fp\":true,\"pl\":[%.4f,%.4f,%.4f],\"h\":%.3f}",
			g_frame, x, y, z, yaw, pitch, roll, vfov, fx, fy, fz, yaw);
		if (!flag("nocam"))
			g_ws.send(msg);
		compositor::set_host_pose(yaw, pitch, roll, vfov, x, y, z);
		if (!flag("noground"))
			send_ground();
		write_blocks();
		if (!flag("noinput"))
			forward_input(rt);
	}
}
