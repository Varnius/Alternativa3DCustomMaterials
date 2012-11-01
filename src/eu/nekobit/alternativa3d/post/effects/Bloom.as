package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	/**
	 * Depth of field post effect.
	 * 
	 * @author Varnius
	 */
	public class Bloom extends BlurBase
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var thresholdProgram:ShaderProgram;
		private var finalProgram:ShaderProgram;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget1:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget2:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget3:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget4:Texture;
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var constant:Vector.<Number> = new <Number>[0, 0, 0, 0];
		
		/**
		 * Color threshold.
		 */
		public var threshold:Number = 0.3;
		
		/**
		 * Saturation of original scene.
		 */
		public var sourceSaturation:Number = 1.0;
		
		/**
		 * Saturation of bloom.
		 */
		public var bloomSaturation:Number = 1.3;
		
		/**
		 * Blend maount of original scene.
		 */
		public var sourceIntensity:Number = 1.0;
		
		/**
		 * Blend amount of bloom.
		 */
		public var bloomIntensity:Number = 1.0;
		
		public function Bloom()
		{
			blendMode = EffectBlendMode.NONE;
			overlay.effect = this;
			needsScene = true;
			needsOverlay = false;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function update(stage3D:Stage3D, camera:Camera3D):void
		{
			super.update(stage3D, camera);
			
			if(camera == null || stage3D == null)
			{
				return;
			}
			
			/*-------------------
			Update cache
			-------------------*/
			
			var contextJustUpdated:Boolean = false;
			
			if(stage3D.context3D != cachedContext3D)
			{
				cachedContext3D = stage3D.context3D;
				
				var programs:Dictionary = programCache[cachedContext3D];
				
				// No programs created yet
				if(programs == null)
				{					
					programs = new Dictionary();
					programCache[cachedContext3D] = programs;
					
					finalProgram = getFinalProgram();
					thresholdProgram = getThresholdProgram();
					finalProgram.upload(cachedContext3D);
					thresholdProgram.upload(cachedContext3D);					
					
					programs["FinalProgram"] = finalProgram;
					programs["ThresholdProgram"] = thresholdProgram;
				}
				else
				{
					finalProgram = programs["FinalProgram"];
					thresholdProgram = programs["ThresholdProgram"];
				}
				
				contextJustUpdated = true;
			}
			
			// Handle render target textures
			if(contextJustUpdated || prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{
				renderTarget1 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);				
				renderTarget2 = cachedContext3D.createTexture(prerenderTextureWidth / 2, prerenderTextureHeight / 2, Context3DTextureFormat.BGRA, true);
				renderTarget3 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				renderTarget4 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
				contextJustUpdated = false;
			}			
			
			/*-------------------
			Render scene with
			color threshold
			-------------------*/
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
			
			constant[0] = threshold;
			constant[3] = 1 - threshold;
			
			// Set constants
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, constant, 1);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, postRenderer.cachedScene);
			
			// Set program
			cachedContext3D.setProgram(thresholdProgram.program);
			
			// Render
			cachedContext3D.setRenderToTexture(renderTarget1);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();
			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);			
			stage3D.context3D.setRenderToBackBuffer();
			
			/*-------------------
			Downsample scene			
			-------------------*/		
						
			resample(renderTarget1, renderTarget2);
			resample(renderTarget2, renderTarget3);	
			
			/*-------------------
			Blur downsampled scene			
			-------------------*/
			
			blur(renderTarget3, renderTarget4, prerenderTextureWidth / 4, prerenderTextureHeight / 4);
			
			/*-------------------
			Upsample
			-------------------*/
			
			resample(renderTarget3, renderTarget2);
			resample(renderTarget2, renderTarget1);
			
			/*-------------------
			Render final view
			-------------------*/
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			// Set constants 			
			constant[0] = sourceIntensity;
			constant[1] = bloomIntensity;
			constant[2] = sourceSaturation;
			constant[3] = bloomSaturation;			
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, constant, 1);
			
			constant[0] = 0.3;
			constant[1] = 0.59;
			constant[2] = 0.11;
			constant[3] = 1.0;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, constant, 1);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, postRenderer.cachedScene);
			cachedContext3D.setTextureAt(1, renderTarget1);		
			
			// Set program
			cachedContext3D.setProgram(finalProgram.program);			
			
			// Combine
			cachedContext3D.setRenderToTexture(postRenderer.cachedSceneTmp);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);				
			stage3D.context3D.setRenderToBackBuffer();
			
			// Clean up
			cachedContext3D.setVertexBufferAt(0, null);
			cachedContext3D.setVertexBufferAt(1, null);
			cachedContext3D.setTextureAt(0, null);
			cachedContext3D.setTextureAt(1, null);
			
			// Swap render targets in postRenderer
			var tmp:Texture = postRenderer.cachedScene;
			postRenderer.cachedScene = postRenderer.cachedSceneTmp;
			postRenderer.cachedSceneTmp = tmp;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function dispose():void
		{
			if(renderTarget1 != null)
			{
				renderTarget1.dispose();			
				renderTarget2.dispose();
				renderTarget3.dispose();
				renderTarget4.dispose();
			}
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		private function getFinalProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(finalVertexProcedure);
			fragmentLinker.addProcedure(finalFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		private function getThresholdProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(thresholdVertexProcedure);
			fragmentLinker.addProcedure(thresholdFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		/*---------------------------
		Final render program
		---------------------------*/
		
		/**
		 * @private
		 */
		static alternativa3d const finalVertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUV",
			
			// Move UV coords to varying-0
			"mov v0 a1",
			// Set vertex position as output
			"mov o0 a0"			
		], "FinalVertex");
		
		/**
		 * @private
		 */
		static alternativa3d const finalFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sRegularScene",
			"#s1=sThresholdScene",
			"#c0=cParams",
			"#c1=cColor",
			"#v0=vUV",
			
			// Sample regular scene
			"tex t0,v0,s0 <2d,clamp,linear>",			
			// Sample threshol scene
			"tex t1,v0,s1 <2d,clamp,linear>",
			
			// Adjust regular scene color saturation
			"dp3 t2.xyz t0.xyz c1.xyz",
			// lerp: x + s * (y - x)
			"sub t3.xyz t0.xyz t2.xyz",
			"mul t3.xyz t3.xyz c0.zzz",
			"add t0.xyz t2.xyz t3.xyz",
			
			// Adjust threshold scene color saturation
			"dp3 t2.xyz t1.xyz c1.xyz",
			// lerp: x + s * (y - x)
			"sub t3.xyz t1.xyz t2.xyz",
			"mul t3.xyz t3.xyz c0.www",
			"add t1.xyz t2.xyz t3.xyz",
			
			// Adjust color intensity
			"mul t0.xyz t0.xyz c0.x",
			"mul t1.xyz t1.xyz c0.y",
			
			// 1 - saturate(bloomColor)
			"sat t2.xyz t1.xyz",
			"sub t2.xyz c1.www t2.xyz",			
			
			// Darken original scene where bloom is bright
			"mul t0.xyz t0.xyz t2.xyz",
			
			// Add both samples
			"add t0 t0 t1",
			"mov t0.w c1.w",
			
			// Return final color
			"mov o0 t0",
		], "FinalFragment");
		
		/*---------------------------
		Threshold program
		---------------------------*/
		
		/**
		 * @private
		 */
		static alternativa3d const thresholdVertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUV",
			
			// Move UV coords to varying-0
			"mov v0 a1",
			// Set vertex position as output
			"mov o0 a0"			
		], "ThresholdVertex");
		
		/**
		 * @private
		 */
		static alternativa3d const thresholdFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sRegularScene",
			// x = Threshold, w = 1 - Threshold
			"#c0=cThreshold",
			"#v0=vUV",
			
			// Formula: saturate((Color – Threshold) / (1 – Threshold))			
			// Get color
			"tex t0,v0,s0 <2d,clamp,linear>",
			// Color - Threshold
			"sub t0.xyz t0.xyz c0.xxx",
			// (Color – Threshold) / (1 – Threshold)
			"mul t0.xyz t0.xyz c0.www",
			// Saturate
			"sat t0 t0",
			
			// Return final color
			"mov o0 t0",
		], "ThresholdFragment");
	}
}