package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.core.CameraOverlay;
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	import eu.nekobit.alternativa3d.post.PostEffectRenderer;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;

	/**
	 * Base class for all post effects.
	 * 
	 * @author Varnius
	 */
	public class PostEffect
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var resampleProgram:ShaderProgram;
		protected var _enabled:Boolean = true;
		
		/**
		 * @private
		 * Indicates whether this effects needs postRenderer to render scene into texture.
		 */
		alternativa3d var needsScene:Boolean = false;
		
		/**
		 * @private
		 * Indicates whether this effects needs postRenderer to render depth map into texture.
		 */
		alternativa3d var needsDepth:Boolean = false;
		
		/**
		 * @private
		 * Indicates whether this effects can use overlay.
		 */
		alternativa3d var needsOverlay:Boolean = true;	
		
		/**
		 * @private
		 * Next effect in the list.
		 */
		alternativa3d var next:PostEffect;
		
		/**
		 * @private
		 * Camera overlay to render effect to.
		 */
		alternativa3d var overlay:CameraOverlay = new CameraOverlay();
		
		/**
		 * @private
		 * Used to acces renderer-level render target cache (like regular scene in the texture or depth map).
		 */
		alternativa3d var postRenderer:PostEffectRenderer;
		
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
			if(camera == null || stage3D == null || !_enabled)
			{
				return;
			}			
			
			/*-------------------
			Update cache
			-------------------*/
			
			if(stage3D.context3D != cachedContext3D)
			{
				cachedContext3D = stage3D.context3D;
				upload(cachedContext3D);
				
				var programs:Dictionary = programCache[cachedContext3D];
				
				// No programs created yet
				if(programs == null)
				{					
					programs = new Dictionary();
					programCache[cachedContext3D] = programs;
					resampleProgram = getResampleProgram();
					resampleProgram.upload(cachedContext3D);					
					programs["ResampleProgram"] = resampleProgram;
				}
				else 
				{
					resampleProgram = programs["ResampleProgram"];
				}
			}
			
			/*if(!needsOverlay)
			{
				return;
			}*/
			
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
			if(needsOverlay)
			{
				overlay.geometry.upload(context3D);
			}
		}
		
		/**
		 * @private
		 * Dispose resources associated with effect.
		 */
		alternativa3d function dispose():void			
		{			
			if(needsOverlay)
			{
				overlay.geometry.dispose();
			}
		}
		
		/*--------------------
		Internal filters
		--------------------*/
		
		/**
		 * Resamples source texture to target texture.
		 * For example, if target texture is smaller than source texture, downsampling occurs.
		 */
		protected function resample(source:Texture, target:Texture):void
		{
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, source);
			
			// Set program
			cachedContext3D.setProgram(resampleProgram.program);
			
			// Render blur
			cachedContext3D.setRenderToTexture(target);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();
			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);			
			cachedContext3D.setRenderToBackBuffer();
		}
		
		/*---------------------------
		Resample program
		---------------------------*/
		
		private function getResampleProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(resampleVertexProcedure);
			fragmentLinker.addProcedure(resampleFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		static protected const resampleVertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUV",
			
			// Move UV coords to varying-0
			"mov v0 a1",
			// Set vertex position as output
			"mov o0 a0"			
		], "ResampleVertex");
		
		static protected const resampleFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sSource",
			"#v0=vUV",
			
			// Sample source texture	
			"tex t0,v0,s0 <2d,clamp,linear>",
			"mov o0 t0",
		], "ResampleFragment");
		
		/*---------------------------
		Getters/setters
		---------------------------*/
		
		/**
		 * Enables/disables the effect. Not implemented yet.
		 */
		public function get enabled():Boolean
		{
			return _enabled;
		}
		public function set enabled(value:Boolean):void
		{
			_enabled = value;
		}
	}
}