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
	public class DepthOfField extends BlurBase
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
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
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget5:Texture;
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var DOFConstants:Vector.<Number> = new <Number>[0, 0, 0, 0];
		
		/**
		 * Distance.
		 */
		public var distance:Number = 0.0;
		
		/**
		 * Range.
		 */
		public var range:Number = 0.2;
		
		public function DepthOfField()
		{
			blendMode = EffectBlendMode.ALPHA;
			overlay.effect = this;
			needsScene = needsDepth = true;
			blurX = blurY = 0.4;
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
					finalProgram.upload(cachedContext3D);
					
					programs["FinalProgram"] = finalProgram;
				}
				else 
				{
					finalProgram = programs["FinalProgram"];
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
				renderTarget5 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
				contextJustUpdated = false;
			}
			
			/*-------------------
			Downsample scene			
			-------------------*/		
			
			resample(postRenderer.cachedScene, renderTarget2);
			resample(renderTarget2, renderTarget3);	
		
			/*-------------------
			Blur regular scene
			-------------------*/			
			
			blur(renderTarget3, renderTarget4, prerenderTextureWidth / 4, prerenderTextureHeight / 4);
			
			/*-------------------
			Upsample scene		
			-------------------*/
			
			resample(renderTarget3, renderTarget2);
			resample(renderTarget2, renderTarget1);
			
			/*-------------------
			Render final view
			-------------------*/
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);	
			
			DOFConstants[0] = camera.farClipping / (camera.farClipping - camera.nearClipping);
			DOFConstants[1] = camera.nearClipping * DOFConstants[0];
			DOFConstants[2] = distance;
			DOFConstants[3] = range;
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, DOFConstants, 1);			
			
			// Set samplers
			cachedContext3D.setTextureAt(0, postRenderer.cachedDepthMap);
			cachedContext3D.setTextureAt(1, renderTarget1);		
			
			// Set program
			cachedContext3D.setProgram(finalProgram.program);			
			
			// Render final scene
			cachedContext3D.setRenderToTexture(renderTarget5);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);				
			stage3D.context3D.setRenderToBackBuffer();
			
			// Clean up
			cachedContext3D.setVertexBufferAt(0, null);
			cachedContext3D.setVertexBufferAt(1, null);
			cachedContext3D.setTextureAt(0, null);
			cachedContext3D.setTextureAt(1, null);
			
			// Pass changes to overlay
			overlay.diffuseMap = renderTarget5;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function dispose():void
		{
			if(renderTarget1)
			{
				renderTarget1.dispose();
				renderTarget2.dispose();
				renderTarget3.dispose();
				renderTarget4.dispose();
				renderTarget5.dispose();
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
		
		/*---------------------------
		Final render program
		---------------------------*/
		
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
		
		static alternativa3d const finalFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDepthMap",
			"#s1=sBlurredScene",
			// c0.xyzw = far/ (-Near * Far)/distance/range
			"#c0=cConstants",
			"#v0=vUV",
			
			// Sample depth map
			"tex t0,v0,s0 <2d,clamp,linear>",
			// Sample blurred scene
			"tex t1,v0,s1 <2d,clamp,linear>",
			
			// Calculate blur factor
			
			// fDepth - Far
			//"sub t0.x t0.x c0.x",
			// fSceneZ = (-Near * Far) / (fDepth - Far)
			//"div t0.x c0.y t0.x",
			// fSceneZ - Distance,
			"sub t0.x t0.x c0.z",
			// div
			"div t0.x t0.x c0.w",
			// Get absolute value
			"abs t0.x t0.x",
			// Clamp value in range [0, 1]
			"sat t0.x t0.x",
			
			// Use blur factor as final color alpha
			"mov t1.w t0.x",
			
			// Return final color
			"mov o0 t1",
		], "FinalFragment");
	}
}