package dev.sbcraft.client.mixin;

import dev.sbcraft.Passthrough;
import net.minecraft.client.renderer.ScreenEffectRenderer;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * No "camera inside a block" overlay while SB drives the camera: SB's camera often sits inside the invisible barriers
 * that stand in for SB's walls (they're on a 1 m grid), and Minecraft would paint that block over the whole screen.
 */
@Mixin(ScreenEffectRenderer.class)
abstract class ScreenEffectRendererMixin {
	@Inject(method = "getViewBlockingState", at = @At("HEAD"), cancellable = true)
	private static void sbcraft$noInWallOverlay(final Player player, final CallbackInfoReturnable<BlockState> cir) {
		if (Passthrough.active) {
			cir.setReturnValue(null);
		}
	}
}
