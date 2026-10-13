// SBCraft.addon64: a ReShade add-on that puts Minecraft inside FNAF: Security Breach. ReShade loads it from its
// own folder (SB's Win64 folder, next to ReShade as dxgi.dll).
#include "compositor.h"
#include "host.h"
#include <windows.h>
#include <reshade.hpp>

extern "C" __declspec(dllexport) const char *NAME = "SBCraft";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
	"Minecraft inside Security Breach: SB's camera drives Minecraft, Minecraft's picture is depth-composited into SB.";

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
	switch (reason)
	{
	case DLL_PROCESS_ATTACH:
		if (!compositor::try_register(module))
			return FALSE;
		break;
	case DLL_PROCESS_DETACH:
		host::stop();
		compositor::unregister(module);
		break;
	}
	return TRUE;
}
