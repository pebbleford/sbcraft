// SBCraft.exe: what the Steam shortcut runs. Starts SBCraft.ps1 (next to this exe) with no console window and waits
// for it, so Steam shows SBCraft as playing until Security Breach quits. Extra arguments are passed to the script.
#include <windows.h>
#include <string>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR args, int)
{
	wchar_t exe[MAX_PATH];
	GetModuleFileNameW(nullptr, exe, MAX_PATH);
	std::wstring dir(exe);
	dir = dir.substr(0, dir.find_last_of(L"\\/"));
	const std::wstring script = dir + L"\\SBCraft.ps1";
	if (GetFileAttributesW(script.c_str()) == INVALID_FILE_ATTRIBUTES)
	{
		MessageBoxW(nullptr, (L"SBCraft.ps1 is missing next to SBCraft.exe:\n" + script).c_str(), L"SBCraft", MB_ICONERROR);
		return 1;
	}
	std::wstring cmd = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + L"\"";
	if (args && *args)
		cmd += std::wstring(L" ") + args;
	STARTUPINFOW si = {sizeof(si)};
	si.dwFlags = STARTF_USESHOWWINDOW;
	si.wShowWindow = SW_HIDE;
	PROCESS_INFORMATION pi = {};
	if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, dir.c_str(), &si, &pi))
	{
		MessageBoxW(nullptr, L"Couldn't start PowerShell.", L"SBCraft", MB_ICONERROR);
		return 1;
	}
	WaitForSingleObject(pi.hProcess, INFINITE);
	DWORD code = 0;
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hProcess);
	CloseHandle(pi.hThread);
	return int(code);
}
