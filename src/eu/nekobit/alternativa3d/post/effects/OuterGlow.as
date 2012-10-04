package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.core.cameras.RenderToTextureCamera;
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	import eu.nekobit.alternativa3d.utils.ObjectList;
	
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
	 * Outer glow effect. Use <code>applyGlowToObject</code> method to apply glow to
	 * an object and <code>removeGlowFromObject</code> to remove the effect.
	 * 
	 * @author Varnius
	 */
	public class OuterGlow extends PostEffect
	{		
		// Program cache		
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;			
		private var blurProgram:ShaderProgram;
		
		// Render targets for internal rendering		
		alternativa3d var renderTarget1:Texture;
		alternativa3d var renderTarget2:Texture;
		alternativa3d var renderTarget3:Texture;
		
		private var hOffset:Number;
		private var vOffset:Number;
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var filterCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10);
		
		// Texture offsets for convolution shader
		private var textureOffsets:Vector.<Number> = new <Number>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		
		// Convolution kernel values
		private var convValues:Vector.<Number> = new <Number>[
			0.09, 0.11, 0.18, 0.24, 0.18, 0.11, 0.09, 0
		];
		
		/**
		 * Glow blending degree.
		 */
		public var blendAmount:Number = 1.0;
			
		/**
		 * Glow color red component.
		 */
		public var colorR:Number = 1.0;
		
		/**
		 * Glow color green component.
		 */
		public var colorG:Number = 0.0;
		
		/**
		 * Glow color blue component.
		 */
		public var colorB:Number = 0.0;
		
		/**
		 * Horizontal glow amount
		 */
		public var glowX:Number = 1.0;
		
		/**
		 * Vertical glow amount
		 */
		public var glowY:Number = 1.0;		
		
		/**
		 * Creates a new instance of this effect.
		 */
		public function OuterGlow()
		{
			filterCamera.filterObjects = true;
			blendMode = EffectBlendMode.ADD;
			overlay.effect = this;
		}		
		
		/**
		 * Adds an object to for filter rendering. If filterObjects property is set only
		 * objects added using this method will be rendered when render() method is called.
		 * 
		 * @param object Object to add.
		 */
		public function applyGlowToObject(object:Object3D):void
		{
			var curr:ObjectList = filterCamera.renderOnly;
			
			// List is not created yet
			if(curr == null)
			{
				filterCamera.renderOnly = new ObjectList();
				filterCamera.renderOnly.object = object;
			}
			// Add to the end of the list if list exists
			else 
			{
				while(curr.next != null)
				{
					curr = curr.next;
				}
				
				curr.next = new ObjectList();
				curr.next.object = object;
			}
		}
		
		/**
		 * Removes outer glow from specified object.
		 * 
		 * @param object Object to remove outer glow from.
		 */
		public function removeGlowFromObject(object:Object3D):void
		{
			var curr:ObjectList = filterCamera.renderOnly;
			var prev:ObjectList = curr;
							
			while(curr != null)
			{
				if(curr.object == object)
				{
					if(prev == curr)
					{
						filterCamera.renderOnly = curr.next;
					}
					else
					{
						prev.next = curr.next;
					}
				}
				
				prev = curr;
				curr = curr.next;
			}
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
					
					blurProgram = getBlurProgram();
					blurProgram.upload(cachedContext3D);
					
					programs["BlurProgram"] = blurProgram;
				}
				else 
				{
					blurProgram = programs["BlurProgram"];
				}
				
				contextJustUpdated = true;
			}
			
			// Handle render target textures
			if(contextJustUpdated || renderTarget1 == null || renderTarget2 == null || renderTarget3 == null|| prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{				
				renderTarget1 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				renderTarget2 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				renderTarget3 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				hOffset = 1 / prerenderTextureWidth;
				vOffset = 1 / prerenderTextureHeight;
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
			}
			
			var oldAlpha:Number = camera.view.backgroundAlpha;			
			
			// Copy camera properties
			filterCamera.setPosition(camera.x, camera.y, camera.z);
			filterCamera.rotationX = camera.rotationX;
			filterCamera.rotationY = camera.rotationY;
			filterCamera.rotationZ = camera.rotationZ;
			filterCamera.fov = camera.fov;
			filterCamera.nearClipping = camera.nearClipping;
			filterCamera.farClipping = camera.farClipping;
			filterCamera.orthographic = camera.orthographic;
			
			// Reuse same view
			filterCamera.view = camera.view;
			filterCamera.view.backgroundAlpha = 0;
			camera.parent.addChild(filterCamera);
			
			/*-------------------
			Render regular scene
			-------------------*/
			
			// Use custom camera to draw only objects that should have glow applied
			filterCamera.texture = renderTarget3;			
			filterCamera.render(stage3D);
			
			camera.parent.removeChild(filterCamera);
			camera.view.backgroundAlpha = oldAlpha;
			stage3D.context3D.setRenderToBackBuffer();		
			
			/*-------------------
			Horizontal blur pass
			-------------------*/
					
			textureOffsets[0]  = -3 * hOffset * glowX;
			textureOffsets[4]  = -2 * hOffset * glowX;
			textureOffsets[8]  =     -hOffset * glowX;
			textureOffsets[12] =  0;
			textureOffsets[16] =      hOffset * glowX;
			textureOffsets[20] =  2 * hOffset * glowX;
			textureOffsets[24] =  3 * hOffset * glowX;			
			
			// Set attributes
			stage3D.context3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			stage3D.context3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
			
			// Set constants 
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
		
			// Set samplers
			stage3D.context3D.setTextureAt(0, renderTarget3);
			
			// Set program
			stage3D.context3D.setProgram(blurProgram.program);
			
			// Render intermediate convolution result
			stage3D.context3D.setRenderToTexture(renderTarget2);
			stage3D.context3D.setBlendFactors(Context3DBlendFactor.SOURCE_ALPHA, Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
			stage3D.context3D.clear(colorR, colorG, colorB, 0);
			stage3D.context3D.drawTriangles(overlayIndexBuffer);			
			stage3D.context3D.present();
			
			// Reset texture offsets
			textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;			
			
			/*-------------------
			Vertical blur pass
			-------------------*/			
			
			textureOffsets[1]  = -3 * vOffset * glowY;
			textureOffsets[5]  = -2 * vOffset * glowY;
			textureOffsets[9]  =     -vOffset * glowY;
			textureOffsets[13] =  0;
			textureOffsets[17] =      vOffset * glowY;
			textureOffsets[21] =  2 * vOffset * glowY;
			textureOffsets[25] =  3 * vOffset * glowY;
			
			// Set attributes
			stage3D.context3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			stage3D.context3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			// Set constants 
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
			
			// Set samplers
			stage3D.context3D.setTextureAt(0, renderTarget2);
			
			// Set program
			stage3D.context3D.setProgram(blurProgram.program);
			
			// Render intermediate convolution result
			stage3D.context3D.setRenderToTexture(renderTarget1);
			stage3D.context3D.setBlendFactors(Context3DBlendFactor.SOURCE_ALPHA, Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
			stage3D.context3D.clear(0,0,0,0);
			stage3D.context3D.drawTriangles(overlayIndexBuffer);			
			stage3D.context3D.present();
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] = 0;
			textureOffsets[21] = 0;
			textureOffsets[25] = 0;	
			
			// Clean up
			cachedContext3D.setTextureAt(0, null);
			stage3D.context3D.setVertexBufferAt(0, null);
			stage3D.context3D.setVertexBufferAt(1, null);	
			
			// Pass changes to overlay
			// Use mask (alpha channel of glowRenderTarget3) to display only outer glow around the object
			overlay.diffuseMap = renderTarget1;
			overlay.maskMap = renderTarget3;
			overlay.blendAmount = blendAmount;
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
		
		/*---------------------------
		Blur shaders
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
		], "vertexProcedure");
		
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
		], "fragmentProcedure");
	}
}