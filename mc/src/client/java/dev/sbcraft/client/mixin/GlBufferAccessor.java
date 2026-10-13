package dev.sbcraft.client.mixin;

import com.mojang.blaze3d.opengl.GlBuffer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

/** The GL name of a GpuBuffer, so the depth readback can pack into it. */
@Mixin(GlBuffer.class)
public interface GlBufferAccessor {
	@Accessor("handle")
	int sbcraft$handle();
}
