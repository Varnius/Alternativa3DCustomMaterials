package eu.nekobit.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	
	import eu.nekobit.core.CameraOverlay;
	import eu.nekobit.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.VertexBuffer3D;
	
	use namespace alternativa3d;

	/**
	 * Base class for all post effects.
	 * 
	 * @author Varnius
	 */
	public class PostEffect
	{
		/**
		 * Prerender texture width.
		 */
		public var prerenderTextureWidth:Number = 256;
		
		/**
		 * Prerender texture height.
		 */
		public var prerenderTextureHeight:Number = 256;
		
		/**
		 * Effect blend mode.
		 */
		public var blendMode:String = EffectBlendMode.ALPHA;
		
		/**
		 * Level of anti-aliasing for render textures. Not supported by FP (as of 11.4) yet.
		 */
		public var antiAlias:int = 0;
		
		/**
		 * @private
		 */
		alternativa3d var next:PostEffect;
		
		// Vertex/UV and index buffers for simple render quad geometry
		protected var overlayVertexBuffer:VertexBuffer3D;
		protected var overlayIndexBuffer:IndexBuffer3D;
		protected var vertices:Vector.<Number> = new <Number>[-1, 1, 0, 0, 0, -1, -1, 0, 0, 1, 1,  1, 0, 1, 0, 1, -1, 0, 1, 1];
		protected var indices:Vector.<uint> = new <uint>[0,1,2,2,1,3];
		
		/**
		 * @private
		 * Camera overlay to render effect to.
		 */
		alternativa3d var overlay:CameraOverlay = new CameraOverlay();
		
		/**
		 * @private
		 */
		public function PostEffect()
		{
			// ..
		}
		
		/**
		 * @private
		 * Updates effect.
		 * 
		 * @param stage3D Instance of Stage3D used for rendering.
		 * @param camera Camera used for rendering.
		 */
		alternativa3d function update(stage3D:Stage3D, camera:Camera3D):void
		{
			switch(blendMode)
			{
				case EffectBlendMode.NONE:
					overlay.blendFactorSource = Context3DBlendFactor.ONE;
					overlay.blendFactorDestination = Context3DBlendFactor.ZERO;
					break;
				case EffectBlendMode.ADD:
					overlay.blendFactorSource = Context3DBlendFactor.ONE;
					overlay.blendFactorDestination = Context3DBlendFactor.ONE;
					break;
				case EffectBlendMode.ALPHA:
					overlay.blendFactorSource = Context3DBlendFactor.SOURCE_ALPHA;
					overlay.blendFactorDestination = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
					break;
				case EffectBlendMode.MULTIPLY:
					overlay.blendFactorSource = Context3DBlendFactor.DESTINATION_COLOR;
					overlay.blendFactorDestination = Context3DBlendFactor.ZERO;
					break;
			}
		}
		
		/**
		 * @private
		 * Upload resources associated with effect.
		 */
		alternativa3d function upload(context3D:Context3D):void
		{
			overlay.geometry.upload(context3D);
			
			// Init buffers for overlay geometry
			if(overlayVertexBuffer == null)
			{
				overlayVertexBuffer = context3D.createVertexBuffer(4, 5);
				overlayVertexBuffer.uploadFromVector(vertices, 0, 4);
				overlayIndexBuffer = context3D.createIndexBuffer(6);
				overlayIndexBuffer.uploadFromVector(indices, 0, 6);
			}	
		}
		
		/**
		 * @private
		 * Dispose resources associated with effect.
		 */
		alternativa3d function dispose():void			
		{
			overlay.geometry.dispose();
			
			if(overlayVertexBuffer != null)
			{
				overlayVertexBuffer.dispose();
				overlayIndexBuffer.dispose();
			}
		}
	}
}