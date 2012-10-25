package eu.nekobit.alternativa3d.post
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.core.cameras.RenderToTextureCamera;
	import eu.nekobit.alternativa3d.post.effects.PostEffect;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DCompareMode;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.VertexBuffer3D;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;

	/**
	 * The PostRenderer class is used to render post-processing effects such as MappedGlow, OuterGlow, DepthOfField and Bloom.
	 * Some effects triggers rendering the scene into a texture, not backbuffer. In those cases MSAA (standart Stage3D antialiasing)
	 * will not work since it is not supported by Context3D.setRenderToTexture as of Flash Player 11.4. This renderer is currently
	 * incompatible with SSAO post processing effect that can be enabled on Camera3D, except cases when only applied effects are those
	 * that do not require to render scene into texture.
	 * 
	 * @author Varnius
	 */
	public class PostEffectRenderer
	{
		private static var programCache:Dictionary = new Dictionary(true);
		
		private var cachedContext3D:Context3D;
		private var overlayProgram:ShaderProgram;			
		private var camera:Camera3D;
		private var stage3D:Stage3D;			
		private var effectList:PostEffect;		
		private var _textureScale:int = 1;
		private var textureParametersChanged:Boolean = false;
		private var prevViewWidth:Number;
		private var prevViewHeight:Number;
		
		// Render targets
		
		/**
		 * @private
		 */
		alternativa3d var cachedScene:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var cachedSceneTmp:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var cachedDepthMap:Texture;		
		private var _depthCameraInternal:Texture;
		
		// Flags for various render targets
		private var shouldRenderScene:Boolean = false;
		private var shouldRenderDepth:Boolean = false;
		
		/**
		 * @private
		 */
		alternativa3d var prerenderTextureWidth:int;
		
		/**
		 * @private
		 */
		alternativa3d var prerenderTextureHeight:int;
		
		// Used to render regular scene
		private var regularCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10, true);
		
		/*---------------------------
		Vertex/UV and index buffers
		for simple render quad geometry
		---------------------------*/
		
		/**
		 * @private
		 */
		alternativa3d var overlayVertexBuffer:VertexBuffer3D;
		
		/**
		 * @private
		 */
		alternativa3d var overlayIndexBuffer:IndexBuffer3D;
		protected var vertices:Vector.<Number> = new <Number>[-1, 1, 0, 0, 0, -1, -1, 0, 0, 1, 1,  1, 0, 1, 0, 1, -1, 0, 1, 1];
		protected var indices:Vector.<uint> = new <uint>[0,1,2,2,1,3];
		
		/**
		 * Creates a new instance of PostEffectRenderer. 
		 * 
		 * @param stage3D Associated Stage3D instance.
		 * @param stage3D Associated camera.
		 */
		public function PostEffectRenderer(stage3D:Stage3D, camera:Camera3D)
		{
			this.stage3D = stage3D;
			this.camera = camera;	
			
			// Init buffers for overlay geometry
			overlayVertexBuffer = stage3D.context3D.createVertexBuffer(4, 5);
			overlayVertexBuffer.uploadFromVector(vertices, 0, 4);
			overlayIndexBuffer = stage3D.context3D.createIndexBuffer(6);
			overlayIndexBuffer.uploadFromVector(indices, 0, 6);
			
			cachedContext3D = stage3D.context3D;
		}
		
		/*---------------------------
		Public methods
		---------------------------*/
		
		/**
		 * Applies an effect to target camera.
		 * renderToTexture flag must be set to true in order to add such effects as Bloom.
		 * 
		 * @param effect Effect to add.
		 */
		public function addEffect(effect:PostEffect):void
		{			
			var curr:PostEffect = effectList;
			
			effect.postRenderer = this;
			
			// List is not created yet
			if(curr == null)
			{
				effectList = effect;
				
				// Apply camera overlay
				if(effect.needsOverlay)
					camera.addChild(effect.overlay);
				effect.upload(cachedContext3D);
			}
			// Add to the end of the list if list exists
			else 
			{
				while(curr.next != null)
				{
					curr = curr.next;
				}
				
				curr.next = effect;
				if(effect.needsOverlay)
					camera.addChild(effect.overlay);
				effect.upload(cachedContext3D);
			}
			
			checkCapabilities();
		}
		
		/**
		 * Removes single effect.
		 * 
		 * @param effect Effect to remove.
		 */		
		public function removeEffect(effect:PostEffect):void
		{
			var curr:PostEffect = effectList;
			var prev:PostEffect = curr;
			
			while(curr != null)
			{
				if(curr == effect)
				{
					if(prev == curr)
					{
						effectList = curr.next;
						if(curr.needsOverlay)
							camera.removeChild(curr.overlay);
						curr.dispose();
					}
					else
					{
						prev.next = curr.next;
						if(curr.needsOverlay)
							camera.removeChild(curr.overlay);
						curr.dispose();
					}
				}
				
				prev = curr;
				curr = curr.next;
			}
			
			checkCapabilities();
		}
		
		/**
		 * Removes all effects from the camera.
		 */		
		public function removeAllEffects():void
		{		
			var curr:PostEffect = effectList;
							
			while(curr != null)
			{
				curr.dispose();
				if(curr.needsOverlay)
					camera.removeChild(curr.overlay);
				curr = curr.next;
			}
			
			effectList = null;			
			checkCapabilities();
		}
		
		/**
		 * Renders scene. Call this method instead of camera.render().
		 */	
		public function render():void			
		{
			refreshTextures();
			renderTextureCache();
			
			for(var curr:PostEffect = effectList; curr != null; curr = curr.next)
			{
				hideOverlays();
				curr.update(stage3D, camera);
				showOverlays();
			}
			
			// Do not call camera.render() for the second time if scene is already rendered to texture
			// Just output the post-effect render target and all overlays
			if(shouldRenderScene)
			{
				cachedContext3D.setRenderToBackBuffer();
				cachedContext3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
				
				// Draw post-processed scene texture
				cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
				cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
				cachedContext3D.setTextureAt(0, cachedScene);				
				cachedContext3D.setProgram(overlayProgram.program);	
				cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
				cachedContext3D.clear();				
				cachedContext3D.drawTriangles(overlayIndexBuffer);		
				
				// Draw overlays over the scene				
				for(curr= effectList; curr != null; curr = curr.next)
				{
					if(!curr.needsOverlay)
					{
						continue;
					}
					
					cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
					cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
					cachedContext3D.setTextureAt(0, curr.overlay.diffuseMap);				
					cachedContext3D.setProgram(overlayProgram.program);				
					cachedContext3D.setBlendFactors(curr.overlay.blendFactorSource, curr.overlay.blendFactorDestination);				
					cachedContext3D.drawTriangles(overlayIndexBuffer);
				}
				
				// Clean up
				cachedContext3D.setVertexBufferAt(0, null);
				cachedContext3D.setVertexBufferAt(1, null);
				cachedContext3D.setTextureAt(0, null);
				
				// Render to backbuffer
				cachedContext3D.present();	
			}
			else
			{
				// Render as usual, all used overlays are automatically rendered by this method
				// since all of them are attached to the camera as instances of Object3D.
				camera.render(stage3D);
			}
		}
		
		/**
		 * Disposes all resources used by this renderer and its effects. You can not use the instance of PostRenderer after calling dispose(). Instead, create a new one.
		 */
		public function dipose():void
		{
			removeAllEffects();
			overlayIndexBuffer.dispose();
			overlayVertexBuffer.dispose();
		}

		/*----------------------
		Helpers
		----------------------*/
		
		/**
		 * Refresh context3D and texture cache.
		 */
		private function refreshTextures():void			
		{			
			if(textureParametersChanged || prevViewHeight != camera.view._height || prevViewWidth != camera.view._width || cachedContext3D != stage3D.context3D)
			{
				cachedContext3D = stage3D.context3D;
				prevViewWidth = camera.view._width;
				prevViewHeight = camera.view._height;				
				
				// Calculate optimal texture sizes
				var log2Width:int = Math.ceil(Math.log(camera.view._width / _textureScale) / Math.LN2);
				var log2Height:int = Math.ceil(Math.log(camera.view._height / _textureScale) / Math.LN2);
				
				// Clamp
				log2Width = log2Width > 11 ? 11 : log2Width;
				log2Height = log2Height > 11 ? 11 : log2Height;
				
				prerenderTextureWidth = 1 << log2Width;
				prerenderTextureHeight = 1 << log2Height;
				
				// Handle textures
				if(shouldRenderScene)
				{
					cachedScene = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);					
					cachedSceneTmp = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				}
				
				if(shouldRenderDepth)
				{
					//cachedDepthMap = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				}
				
				// Handle program cache				
				var programs:Dictionary = programCache[cachedContext3D];
				
				// No programs created yet
				if(programs == null)
				{					
					programs = new Dictionary();
					programCache[cachedContext3D] = programs;
					overlayProgram = getOverlayProgram();
					overlayProgram.upload(cachedContext3D);					
					programs["OverlayProgram"] = overlayProgram;
				}
				else 
				{
					overlayProgram = programs["OverlayProgram"];
				}
				
				textureParametersChanged = false;
			}
		}
		
		/**
		 * Renders regular efectlesscene to texture
		 */
		private function renderTextureCache():void			
		{		
			// Render regular scene to a texture
			if(shouldRenderScene)
			{
				// Copy camera properties				
				regularCamera.setPosition(camera.x, camera.y, camera.z);				
				regularCamera.rotationX = camera.rotationX;
				regularCamera.rotationY = camera.rotationY;
				regularCamera.rotationZ = camera.rotationZ;
				regularCamera.fov = camera.fov;
				regularCamera.nearClipping = camera.nearClipping;
				regularCamera.farClipping = camera.farClipping;
				regularCamera.orthographic = camera.orthographic;
				
				// Reuse same view				
				regularCamera.view = camera.view;
				
				// todo: effect wrapper for SSAO
				// Copy post properties
				/*regularCamera.effectMode = camera.effectMode;
				regularCamera.effectRate = camera.effectRate;
				regularCamera.blurEnabled = camera.blurEnabled;
				regularCamera.ssaoScale = camera.ssaoScale;
				regularCamera.depthScale = camera.depthScale;
				regularCamera.ssaoAngular = camera.ssaoAngular;*/
				
				// Render depth map to a texture
				if(shouldRenderDepth)
				{
					regularCamera.effectMode = RenderToTextureCamera.DEPTH_FOR_CACHE;
				}
				else
				{
					regularCamera.effectMode = Camera3D.MODE_COLOR;
				}
				
				/*------------------
				Render regular scene
				------------------*/
				
				camera.parent.addChild(regularCamera);
				
				// todo: antialiasing not supported by FP
				regularCamera.sceneRenderTarget = cachedScene;
				regularCamera.render(stage3D);
				cachedDepthMap = regularCamera.ssaoTexture;
				
				camera.parent.removeChild(regularCamera);
			}
			
			// Render depth map to a texture
			/*if(shouldRenderDepth)
			{
				depthCamera.texWidth = prerenderTextureWidth;
				depthCamera.texHeight = prerenderTextureHeight;
				
				// Copy camera properties
				depthCamera.setPosition(camera.x, camera.y, camera.z);				
				depthCamera.rotationX = camera.rotationX;
				depthCamera.rotationY = camera.rotationY;
				depthCamera.rotationZ = camera.rotationZ;
				depthCamera.fov = camera.fov;
				depthCamera.nearClipping = camera.nearClipping;
				depthCamera.farClipping = camera.farClipping;
				depthCamera.orthographic = camera.orthographic;
				
				// Reuse same view
				depthCamera.view = camera.view;
				camera.parent.addChild(depthCamera);	
				
				// Can`t set renderToTexture here because this camera uses few of those internally..
				depthCamera.depthMap = cachedDepthMap;
				depthCamera.render(stage3D);
				
				camera.parent.removeChild(depthCamera);
			}*/
		}
		
		private function showOverlays():void
		{
			var curr:PostEffect = effectList;
			
			while(curr != null)
			{
				if(curr.needsOverlay)
					curr.overlay.visible = true;
				curr = curr.next;
			}
		}
		
		private function hideOverlays():void
		{
			var curr:PostEffect = effectList;	
			
			while(curr != null)
			{
				if(curr.needsOverlay)
					curr.overlay.visible = false;
				curr = curr.next;
			}
		}
		
		private function checkCapabilities():void
		{
			var needScene:Boolean = false;
			var needDepth:Boolean = false;
			
			for(var curr:PostEffect = effectList; curr != null; curr = curr.next)
			{	
				if(curr.needsScene)
				{
					needScene = true;
				}					
				
				if(curr.needsDepth)
				{
					needDepth = true;
				}			
			}
			
			if(shouldRenderScene != needScene || shouldRenderDepth != needDepth)
			{
				textureParametersChanged = true;
			}
			
			if(!needScene && cachedScene)
			{
				cachedScene.dispose();
				cachedSceneTmp.dispose();
			}
			
			if(!needDepth && cachedDepthMap)
			{
				//cachedDepthMap.dispose();
				//depthCamera.depthTexture.dispose();
			}
			
			shouldRenderScene = needScene;
			shouldRenderDepth = needDepth;
		}
		
		/*---------------------------
		Getters/setters
		---------------------------*/
		
		/**
		 * Render texture scale.
		 * Example: if width and height of the render area are 1000px and 500px and texture scale value is 1 (default), then
		 * render texture would be 1024px in width and 512px in height. If the scale is 2 then those would be accordingly 512px and 256px.
		 * Therefore, this value scales automatically calculated texture width and height.
		 */
		public function get textureScale():int
		{
			return _textureScale;
		}		
		public function set textureScale(value:int):void
		{
			if(_textureScale != value)
			{
				_textureScale = value;
				textureParametersChanged = true;
			}
		}
		
		/*---------------------------
		Shader programs
		---------------------------*/
		
		private function getOverlayProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(overlayVertexProcedure);
			fragmentLinker.addProcedure(overlayFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		static alternativa3d const overlayVertexProcedure:Procedure = new Procedure(
		[			
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUV",
			
			"mov v0 a1",
			"mov o0 a0",
		], "OverlayVertexProcedure");
		
		static alternativa3d const overlayFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",			
			"#v0=vUV",
			
			"tex t0,v0,s0 <2d,repeat,linear>",
			"mov o0, t0"
		], "OverlayFragmentProcedure");
	}
}