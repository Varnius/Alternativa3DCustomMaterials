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
	import flash.utils.getTimer;
	
	use namespace alternativa3d;

	/**
	 * Outer glow effect. Use <code>applyGlowToObject</code> method to apply glow to
	 * an object and <code>removeGlowFromObject</code> to remove the effect.
	 * 
	 * @author Varnius
	 */
	public class OuterGlow extends BlurBase
	{		
		// Cache
		private var cachedContext3D:Context3D;
		
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
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget6:Texture;
		
		private var propertyChanged:Boolean = false;
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var filterCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10);
		
		/**
		 * Glow blending degree.
		 */
		public var blendAmount:Number = 1.0;
		
		private var _smoothEdges:Boolean = false;
			
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
		 * Creates a new instance of this effect.
		 */
		public function OuterGlow()
		{
			filterCamera.filterObjects = true;
			blendMode = EffectBlendMode.ADD;
			overlay.effect = this;			
			blurClearParamsHorizontal[3] = 0;
			blurClearParamsVertical[3] = 0;	
			blurBlendFactors[0] = blurBlendFactors[2] = Context3DBlendFactor.SOURCE_ALPHA;
			blurBlendFactors[1] = blurBlendFactors[3] = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
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
				contextJustUpdated = true;
			}
			
			// Handle render target textures
			if(contextJustUpdated || propertyChanged || prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{				
				renderTarget1 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				renderTarget2 = cachedContext3D.createTexture(prerenderTextureWidth / 2, prerenderTextureHeight / 2, Context3DTextureFormat.BGRA, true);
				renderTarget3 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				renderTarget4 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				renderTarget5 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				if(_smoothEdges)
				{
					renderTarget6 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				}
				else
				{
					if(renderTarget6)
						renderTarget6.dispose();
				}
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
				propertyChanged = false;
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
			filterCamera.sceneRenderTarget = renderTarget1;			
			filterCamera.render(stage3D);
			
			camera.parent.removeChild(filterCamera);
			camera.view.backgroundAlpha = oldAlpha;
			stage3D.context3D.setRenderToBackBuffer();
			
			/*-------------------
			Downsample scene			
			-------------------*/		
			
			resample(renderTarget1, renderTarget2);
			resample(renderTarget2, renderTarget3);	
			
			/*-------------------
			Blur regular scene
			-------------------*/			
			
			blurClearParamsHorizontal[0] = colorR;
			blurClearParamsHorizontal[1] = colorG;			
			blurClearParamsHorizontal[2] = colorB;
			
			blur(renderTarget3, renderTarget4, prerenderTextureWidth / 4, prerenderTextureHeight / 4);
			
			/*-------------------
			Upsample scene			
			-------------------*/		
			
			resample(renderTarget3, renderTarget2);
			resample(renderTarget2, renderTarget5);			
			
			// Smooth glow edges
			if(_smoothEdges)
			{
				var oldBlurX:Number = blurX;
				var oldBlurY:Number = blurY;	
				
				blurX = 1;
				blurY = 1;
				blur(renderTarget1, renderTarget6, prerenderTextureWidth, prerenderTextureHeight);
				
				blurX = oldBlurX;
				blurY = oldBlurY;
			}					
			
			// Clean up
			cachedContext3D.setTextureAt(0, null);
			stage3D.context3D.setVertexBufferAt(0, null);
			stage3D.context3D.setVertexBufferAt(1, null);
			
			// Pass changes to overlay
			// Use mask map alpha channel to display only outer glow around the object and not on object itself
			overlay.diffuseMap = renderTarget5;
			overlay.maskMap = renderTarget1;
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
				renderTarget4.dispose();
				renderTarget5.dispose();
				
				if(_smoothEdges)
					renderTarget6.dispose();
			}
		}	
		/*----------------------
		Getters/setters
		----------------------*/
		
		/**
		 * If enabled, smoothes glow inner edges by doing additional blur pass.
		 */
		public function get smoothEdges():Boolean
		{
			return _smoothEdges;
		}
		
		/**
		 * @private
		 */
		public function set smoothEdges(value:Boolean):void
		{
			if(value != _smoothEdges)
			{
				_smoothEdges = value;
				propertyChanged = true;
			}			
		}	
	}
}