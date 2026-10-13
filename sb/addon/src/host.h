// SB half of SBCraft: camera, ground and input to the Minecraft mod (see host.cpp).
#pragma once

namespace reshade::api { struct effect_runtime; }

namespace host
{
	void start();
	void stop();
	/// Once per presented frame, before the effects run (camera read at present time).
	void frame(reshade::api::effect_runtime *runtime);
	/// Debug switches: words in <link dir>\addon_flags.txt, read once at start (noupload, nocam, noground, noinput).
	bool flag(const char *name);
}
