package eu.nekobit.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.core.cameras.DepthMapCamera;
	import eu.nekobit.core.cameras.RenderToTextureCamera;
	import eu.nekobit.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	
	use namespace alternativa3d;
	
	/**
	 * Depth of field post effect.
	 */
	public class DepthOfField extends PostEffect
	{
		// Cache	
		private var cachedContext3D:Context3D;
		private var blurProgram:ShaderProgram;
		private var finalProgram:ShaderProgram;
		
		// Texture offsets for blur shader
		private var textureOffsets:Vector.<Number> = new <Number>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		
		// Convolution kernel values for blur shader
		private var convValues:Vector.<Number> = new <Number>[
			0.09, 0.11, 0.18, 0.24, 0.18, 0.11, 0.09, 0
		];
		
		private var hOffset:Number;
		private var vOffset:Number;
		
		alternativa3d var depthMap:Texture;
		alternativa3d var regularScene:Texture;
		alternativa3d var blurTexture1:Texture;
		alternativa3d var blurTexture2:Texture;	
		
		// todo: grab depth map directly from Camera3D somehow :~
		private var depthCamera:DepthMapCamera = new DepthMapCamera(1, 10);
		private var regularCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10);
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
		
		/**
		 * Effect blending degree.
		 */
		public var blendAmount:Number = 1.0;
		
		/**
		 * Horizontal blur amount
		 */
		public var blurX:Number = 1.0;
		
		/**
		 * Vertical blur amount
		 */
		public var blurY:Number = 1.0;
		
		public function DepthOfField()
		{
			blendMode = EffectBlendMode.ALPHA;
			depthCamera.effectMode = 2;
			overlay.effect = this;
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
			
			var contextUpdated:Boolean = false;
			
			if(stage3D.context3D != cachedContext3D)
			{
				cachedContext3D = stage3D.context3D;
				
				blurProgram = getBlurProgram();
				finalProgram = getFinalProgram();
				blurProgram.upload(cachedContext3D);
				finalProgram.upload(cachedContext3D);
				
				contextUpdated = true;
			}
			
			// Handle render target textures
			if(contextUpdated || depthMap == null || prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{
				depthCamera.texWidth = prerenderTextureWidth;
				depthCamera.texHeight = prerenderTextureHeight;
				
				depthMap = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				regularScene = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				blurTexture1 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				blurTexture2 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				hOffset = 1 / prerenderTextureWidth;
				vOffset = 1 / prerenderTextureHeight;
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
				contextUpdated = false;
			}
			
			// Copy camera properties
			depthCamera.setPosition(camera.x, camera.y, camera.z);
			regularCamera.setPosition(camera.x, camera.y, camera.z);
			
			regularCamera.rotationX = depthCamera.rotationX = camera.rotationX;
			regularCamera.rotationY = depthCamera.rotationY = camera.rotationY;
			regularCamera.rotationZ = depthCamera.rotationZ = camera.rotationZ;
			regularCamera.fov = depthCamera.fov = camera.fov;
			regularCamera.nearClipping = depthCamera.nearClipping = camera.nearClipping;
			regularCamera.farClipping = depthCamera.farClipping = camera.farClipping;
			regularCamera.orthographic = depthCamera.orthographic = camera.orthographic;
			
			// Reuse same view
			regularCamera.view = depthCamera.view = camera.view;
			camera.parent.addChild(depthCamera);				
			camera.parent.addChild(regularCamera);
			
			/*-------------------
			Render regular scene
			-------------------*/	

			// todo: antialiasing not supported by FP
			regularCamera.texture = regularScene;	
			regularCamera.render(stage3D);		
			
			/*-------------------
			Render depth map
			-------------------*/
			
			// Can`t set renderToTexture here because this camera uses few of those internally..
			depthCamera.depthMap = depthMap;
			depthCamera.render(stage3D);
			
			camera.parent.removeChild(depthCamera);	
			camera.parent.removeChild(regularCamera);
			
			/*-------------------
			Blur regular scene
			horizontally
			-------------------*/			
			
			textureOffsets[0]  = -3 * hOffset * blurX;
			textureOffsets[4]  = -2 * hOffset * blurX;
			textureOffsets[8]  =     -hOffset * blurX;
			textureOffsets[12] =  0;
			textureOffsets[16] =      hOffset * blurX;
			textureOffsets[20] =  2 * hOffset * blurX;
			textureOffsets[24] =  3 * hOffset * blurX;		
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, regularScene);
			
			// Set program
			cachedContext3D.setProgram(blurProgram.program);
			
			// Render blur
			cachedContext3D.setRenderToTexture(blurTexture1);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();
			
			cachedContext3D.drawTriangles(overlayIndexBuffer);			
			cachedContext3D.present();
			
			// Reset texture offsets
			textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;
			
			/*-------------------
			Blur regular scene
			vertically
			-------------------*/
			
			textureOffsets[1]  = -3 * vOffset * blurY;
			textureOffsets[5]  = -2 * vOffset * blurY;
			textureOffsets[9]  =     -vOffset * blurY;
			textureOffsets[13] =  0;
			textureOffsets[17] =      vOffset * blurY;
			textureOffsets[21] =  2 * vOffset * blurY;
			textureOffsets[25] =  3 * vOffset * blurY;
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, blurTexture1);
			
			// Set program
			cachedContext3D.setProgram(blurProgram.program);
			
			// Render intermediate convolution result
			cachedContext3D.setRenderToTexture(blurTexture2);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();
			
			cachedContext3D.drawTriangles(overlayIndexBuffer);			
			cachedContext3D.present();
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] = 0;
			textureOffsets[21] = 0;
			textureOffsets[25] = 0;
			
			/*-------------------
			Render final view
			-------------------*/			
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			DOFConstants[0] = camera.farClipping / (camera.farClipping - camera.nearClipping);
			DOFConstants[1] = camera.nearClipping * DOFConstants[0];			
			DOFConstants[2] = distance;
			DOFConstants[3] = range;
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, DOFConstants, 1);			
			
			// Set samplers
			cachedContext3D.setTextureAt(0, depthMap);
			cachedContext3D.setTextureAt(1, blurTexture2);		
			
			// Set program
			cachedContext3D.setProgram(finalProgram.program);			
			
			// Render final scene
			cachedContext3D.setRenderToTexture(blurTexture1);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();			
			cachedContext3D.drawTriangles(overlayIndexBuffer);				
			cachedContext3D.present();
			
			// Clean up
			cachedContext3D.setVertexBufferAt(0, null);
			cachedContext3D.setVertexBufferAt(1, null);
			cachedContext3D.setTextureAt(0, null);
			cachedContext3D.setTextureAt(1, null);
			
			// Pass changes to overlay
			overlay.diffuseMap = blurTexture1;
			overlay.blendAmount = blendAmount;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function dispose():void
		{
			if(depthMap != null)
			{
				depthMap.dispose();
				regularScene.dispose();
				blurTexture1.dispose();
				blurTexture2.dispose();
			}
			
			if(depthCamera.depthTexture != null)
			{
				depthCamera.depthTexture.dispose();
			}
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		private function getBlurProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(blurVertexProcedure);
			fragmentLinker.addProcedure(blurFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
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
		
		/*---------------------------
		Blur shader program
		---------------------------*/
		
		static alternativa3d const blurVertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#c0=cUVOffset0",
			"#c1=cUVOffset1",
			"#c2=cUVOffset2",
			"#c3=cUVOffset3",
			"#c4=cUVOffset4",
			"#c5=cUVOffset5",
			"#c6=cUVOffset6",
			//"#c7=cUVOffset7",
			"#v0=vUV0",
			"#v1=vUV1",
			"#v2=vUV2",
			"#v3=vUV3",
			"#v4=vUV4",
			"#v5=vUV5",
			"#v6=vUV6",
			//"#v7=vUV7",
			
			// Add texture offsets, move to varyings
			"add v0 a1 c0",
			"add v1 a1 c1",
			"add v2 a1 c2",
			"add v3 a1 c3",
			"add v4 a1 c4",
			"add v5 a1 c5",
			"add v6 a1 c6",
			//"add v7 a1 c7",
			
			// Set vertex position as output
			"mov o0 a0"
		], "BlurVertex");
		
		static alternativa3d const blurFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",
			"#c0=cConvolutionVals1",
			"#c1=cConvolutionVals2",
			"#v0=vUV0",
			"#v1=vUV1",
			"#v2=vUV2",
			"#v3=vUV3",
			"#v4=vUV4",
			"#v5=vUV5",
			"#v6=vUV6",
			//"#v7=vUV7",
			
			// Apply convolution kernel
			
			"tex t0,v0,s0 <2d,clamp,linear>",
			"tex t1,v1,s0 <2d,clamp,linear>",
			"mul t0 t0 c0.x",
			"mul t1 t1 c0.y",
			"add t0 t0 t1",
			
			"tex t1,v2,s0 <2d,clamp,linear>",
			"tex t2,v3,s0 <2d,clamp,linear>",
			"mul t1 t1 c0.z",
			"mul t2 t2 c0.w",
			"add t0 t0 t1",
			"add t0 t0 t2",
			
			"tex t1,v4,s0 <2d,clamp,linear>",
			"tex t2,v5,s0 <2d,clamp,linear>",
			"mul t1 t1 c1.x",
			"mul t2 t2 c1.y",
			"add t0 t0 t1",
			"add t0 t0 t2",
			
			"tex t1,v6,s0 <2d,clamp,linear>",
			//"tex t2,v7,s0 <2d,clamp,linear>",
			"mul t1 t1 c1.z",
			//"mul t2 t2 c1.w",
			"add t0 t0 t1",
			//"add t0 t0 t2",
			
			"mov o0 t0",
		], "BlurFragment");
	}
}