package eu.nekobit.alternativa3d.core.cameras
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.Debug;
	import alternativa.engine3d.core.Light3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.core.Occluder;
	import alternativa.engine3d.core.RendererContext3DProperties;
	import alternativa.engine3d.materials.EncodeDepthMaterial;
	import alternativa.engine3d.materials.OutputEffect;
	import alternativa.engine3d.materials.SSAOBlur;
	
	import eu.nekobit.alternativa3d.utils.ObjectList;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.textures.Texture;
	import flash.geom.Rectangle;
	import flash.geom.Vector3D;
	
	use namespace alternativa3d;
	
	/**
	 * @private
	 * Internal camera used for rendering scene to texture.
	 * Optionally can render only objects specified in renderOnly list.
	 */
	public class RenderToTextureCamera extends Camera3D
	{
		public static const DEPTH_FOR_CACHE:int = 111;
		
		alternativa3d var renderOnly:ObjectList;		
		alternativa3d var sceneRenderTarget:Texture;
		alternativa3d var filterObjects:Boolean = false;
		alternativa3d var enablePostAndInteractivity:Boolean = false;	
		
		// Copied from base
		private var encDepthMaterial:EncodeDepthMaterial = new EncodeDepthMaterial();
		private var decDepthEffect:OutputEffect = new OutputEffect();
		private var ssaoBlur:SSAOBlur = new SSAOBlur();	
		alternativa3d var depthTexture:Texture;
		alternativa3d var ssaoTexture:Texture;
		alternativa3d var bluredSSAOTexture:Texture;
		private var effectTextureLog2Width:int = -1;
		private var effectTextureLog2Height:int = -1;
		private var _depthScale:int = 0;
		override public function get depthScale():int {
			return _depthScale;
		}
		override public function set depthScale(value:int):void {
			if (depthTexture != null) {
				depthTexture.dispose();
				depthTexture = null;
			}
			_depthScale = (value > 0) ? value : 0;
		}
		private var rect:Rectangle = new Rectangle();
		
		public function RenderToTextureCamera(nearClipping:Number, farClipping:Number, enablePostAndInteractivity:Boolean = false)
		{
			super(nearClipping, farClipping);
			this.enablePostAndInteractivity = enablePostAndInteractivity;
		}
		
		override public function render(stage3D:Stage3D):void
		{
			if (ssaoScale < 0) ssaoScale = 0;
			
			var i:int;
			var j:int;
			var light:Light3D;
			var occluder:Occluder;
			// Error checking
			if (stage3D == null) throw new TypeError("Parameter stage3D must be non-null.");
			// Reset the counters
			numDraws = 0;
			numTriangles = 0;
			// Reset the occluders
			occludersLength = 0;
			// Reset the lights
			lightsLength = 0;
			ambient[0] = 0;
			ambient[1] = 0;
			ambient[2] = 0;
			ambient[3] = 1;
			// Receiving the context
			var currentContext3D:Context3D = stage3D.context3D;
			if (currentContext3D != context3D) {
				if (currentContext3D != null) {
					context3DProperties = context3DPropertiesPool[currentContext3D];
					if (context3DProperties == null) {
						context3DProperties = new RendererContext3DProperties();
						context3DProperties.isConstrained = currentContext3D.driverInfo.lastIndexOf("(Baseline Constrained)") >= 0;
						context3DPropertiesPool[currentContext3D] = context3DProperties;
					}
					context3D = currentContext3D;
				} else {
					context3D = null;
					context3DProperties = null;
				}
			}
			if (context3D != null && view != null && renderer != null && (view.stage != null || view._canvas != null)) {
				renderer.camera = this;
				depthRenderer.camera = this;
				// Projection argument calculating
				calculateProjection(view._width, view._height);
				// Preparing to rendering
				view.configureContext3D(stage3D, context3D, this);
				
				// changed:
				if(effectMode > 0 && enablePostAndInteractivity)
				{
					// update depth texture
					var log2Width:int = Math.ceil(Math.log(view._width/effectRate)/Math.LN2) - ssaoScale;
					var log2Height:int = Math.ceil(Math.log(view._height/effectRate)/Math.LN2) - ssaoScale;
					log2Width = log2Width > 11 ? 11 : log2Width;
					log2Height = log2Height > 11 ? 11 : log2Height;
					if (effectTextureLog2Width != log2Width || effectTextureLog2Height != log2Height || depthTexture == null) {
						if (depthTexture != null) depthTexture.dispose();
						depthTexture = context3D.createTexture(1 << (log2Width - _depthScale), 1 << (log2Height - _depthScale), Context3DTextureFormat.BGRA, true);
						
						if (ssaoTexture != null) ssaoTexture.dispose();
						ssaoTexture = context3D.createTexture(1 << log2Width, 1 << log2Height, Context3DTextureFormat.BGRA, true);
						
						if(effectMode != DEPTH_FOR_CACHE)
						{
							if (bluredSSAOTexture != null) bluredSSAOTexture.dispose();
							bluredSSAOTexture = context3D.createTexture(1 << log2Width, 1 << log2Height, Context3DTextureFormat.BGRA, true);
						}
						
						effectTextureLog2Width = log2Width;
						effectTextureLog2Height = log2Height;
					}
					encDepthMaterial.outputScaleX = view._width/(1 << (effectTextureLog2Width + ssaoScale));
					encDepthMaterial.outputScaleY = view._height/(1 << (effectTextureLog2Height + ssaoScale));
					encDepthMaterial.outputOffsetX = encDepthMaterial.outputScaleX - 1;
					encDepthMaterial.outputOffsetY = 1 - encDepthMaterial.outputScaleY;
				}
				
				// Transformations calculating
				if (transformChanged) composeTransforms();
				localToGlobalTransform.copy(transform);
				globalToLocalTransform.copy(inverseTransform);
				// Searching for upper hierarchy point
				var root:Object3D = this;
				while (root.parent != null) {
					root = root.parent;
					if (root.transformChanged) root.composeTransforms();
					localToGlobalTransform.append(root.transform);
					globalToLocalTransform.prepend(root.inverseTransform);
				}
				
				// Check if object of hierarchy is visible
				if (root.visible) {
					// Calculating the matrix to transform from the camera space to local space
					root.cameraToLocalTransform.combine(root.inverseTransform, localToGlobalTransform);
					// Calculating the matrix to transform from local space to the camera space
					root.localToCameraTransform.combine(globalToLocalTransform, root.transform);
					
					globalMouseHandlingType = root.mouseHandlingType;
					// Checking the culling
					if (root.boundBox != null) {
						calculateFrustum(root.cameraToLocalTransform);
						root.culling = root.boundBox.checkFrustumCulling(frustum, 63);
					} else {
						root.culling = 63;
					}
					// Calculations of content visibility
					if (root.culling >= 0) root.calculateVisibility(this);
					// Calculations  visibility of children
					root.calculateChildrenVisibility(this);
					// Calculations of transformations from occluder space to the camera space
					for (i = 0; i < occludersLength; i++) {
						occluder = occluders[i];
						occluder.localToCameraTransform.calculateInversion(occluder.cameraToLocalTransform);
						occluder.transformVertices(correctionX, correctionY);
						occluder.distance = orthographic ? occluder.localToCameraTransform.l : (occluder.localToCameraTransform.d * occluder.localToCameraTransform.d + occluder.localToCameraTransform.h * occluder.localToCameraTransform.h + occluder.localToCameraTransform.l * occluder.localToCameraTransform.l);
						occluder.enabled = true;
					}
					// Sorting the occluders by disance
					if (occludersLength > 1) sortOccluders();
					// Constructing the volumes of occluders, their intersections, starts from closest
					for (i = 0; i < occludersLength; i++) {
						occluder = occluders[i];
						if (occluder.enabled) {
							occluder.calculatePlanes(this);
							if (occluder.planeList != null) {
								for (j = i + 1; j < occludersLength; j++) { // It is possible, that start value should be 0
									var compared:Occluder = occluders[j];
									if (compared.enabled && compared != occluder && compared.checkOcclusion(occluder, correctionX, correctionY)) compared.enabled = false;
								}
							} else {
								occluder.enabled = false;
							}
						}
						// Reset of culling
						occluder.culling = -1;
					}
					//  Gather the occluders which will affects now
					for (i = 0, j = 0; i < occludersLength; i++) {
						occluder = occluders[i];
						if (occluder.enabled) {
							// Debug
							occluder.collectDraws(this, null, 0, false);
							if (debug && occluder.boundBox != null && (checkInDebug(occluder) & Debug.BOUNDS)) Debug.drawBoundBox(this, occluder.boundBox, occluder.localToCameraTransform);
							occluders[j] = occluder;
							j++;
						}
					}
					occludersLength = j;
					occluders.length = j;
					// Check light influence
					for (i = 0, j = 0; i < lightsLength; i++) {
						light = lights[i];
						light.localToCameraTransform.calculateInversion(light.cameraToLocalTransform);
						if (light.boundBox == null || occludersLength == 0 || !light.boundBox.checkOcclusion(occluders, occludersLength, light.localToCameraTransform)) {
							light.red = ((light.color >> 16) & 0xFF) * light.intensity / 255;
							light.green = ((light.color >> 8) & 0xFF) * light.intensity / 255;
							light.blue = (light.color & 0xFF) * light.intensity / 255;
							// Debug
							light.collectDraws(this, null, 0, false);
							if (debug && light.boundBox != null && (checkInDebug(light) & Debug.BOUNDS)) Debug.drawBoundBox(this, light.boundBox, light.localToCameraTransform);
							
							// Shadows preparing
							if (light.shadow != null) {
								light.shadow.process(this);
							}
							lights[j] = light;
							j++;
						}
						light.culling = -1;
					}
					lightsLength = j;
					lights.length = j;
					
					// Sort lights by types
					if (lightsLength > 0) sortLights(0, lightsLength - 1);
					
					// changed:
					if(enablePostAndInteractivity)
					{
						// Calculating the rays of mouse events
						view.calculateRays(this, (globalMouseHandlingType & Object3D.MOUSE_HANDLING_MOVING) != 0,
							(globalMouseHandlingType & Object3D.MOUSE_HANDLING_PRESSING) != 0,
							(globalMouseHandlingType & Object3D.MOUSE_HANDLING_WHEEL) != 0,
							(globalMouseHandlingType & Object3D.MOUSE_HANDLING_MIDDLE_BUTTON) != 0,
							(globalMouseHandlingType & Object3D.MOUSE_HANDLING_RIGHT_BUTTON) != 0);
						for (i = origins.length; i < view.raysLength; i++) {
							origins[i] = new Vector3D();
							directions[i] = new Vector3D();
						}
						raysLength = view.raysLength;
					}
					
					var r:Number = ((view.backgroundColor >> 16) & 0xff)/0xff;
					var g:Number = ((view.backgroundColor >> 8) & 0xff)/0xff;
					var b:Number = (view.backgroundColor & 0xff)/0xff;
					if (view._canvas != null) {
						r *= view.backgroundAlpha;
						g *= view.backgroundAlpha;
						b *= view.backgroundAlpha;
					}
					
					// changed:
					if(!enablePostAndInteractivity && sceneRenderTarget != null)
					{
						context3D.setRenderToTexture(sceneRenderTarget, true);
					}
					
					context3D.clear(r, g, b, view.backgroundAlpha);
					
					// Check getting in frustum and occluding
					if (root.culling >= 0 && (root.boundBox == null || occludersLength == 0 || !root.boundBox.checkOcclusion(occluders, occludersLength, root.localToCameraTransform))) {
						// Check if the ray crossing the bounding box
						if (globalMouseHandlingType > 0 && root.boundBox != null) {
							calculateRays(root.cameraToLocalTransform);
							root.listening = root.boundBox.checkRays(origins, directions, raysLength);
						} else {
							root.listening = globalMouseHandlingType > 0;
						}
						// Check if object needs in lightning
						var excludedLightLength:int = root._excludedLights.length;
						if (lightsLength > 0 && root.useLights) {
							// Pass the lights to children and calculate appropriate transformations
							var childLightsLength:int = 0;
							if (root.boundBox != null) {
								for (i = 0; i < lightsLength; i++) {
									light = lights[i];
									// Checking light source for existing in excludedLights
									j = 0;
									while (j<excludedLightLength && root._excludedLights[j]!=light)	j++;
									if (j<excludedLightLength) continue;
									
									light.lightToObjectTransform.combine(root.cameraToLocalTransform, light.localToCameraTransform);
									// Detect influence
									if (light.boundBox == null || light.checkBound(root)) {
										childLights[childLightsLength] = light;
										childLightsLength++;
									}
								}
							} else {
								// Calculate transformation from light space to object space
								for (i = 0; i < lightsLength; i++) {
									light = lights[i];
									// Checking light source for existing in excludedLights
									j = 0;
									while (j<excludedLightLength && root._excludedLights[j]!=light)	j++;
									if (j<excludedLightLength) continue;
									
									light.lightToObjectTransform.combine(root.cameraToLocalTransform, light.localToCameraTransform);
									
									childLights[childLightsLength] = light;
									childLightsLength++;
								}
							}
							
							// changed: added filter
							if(renderOnly != null && filterObjects)
							{
								if(!shouldRender(root))
								{
									root.culling = -1;
								}
							}
							
							root.collectDraws(this, childLights, childLightsLength, root.useShadow);
						} 
						else
						{
							// changed: added filter
							if(renderOnly != null && filterObjects)
							{
								if(!shouldRender(root))
								{
									root.culling = -1;
								}
							}
							
							root.collectDraws(this, null, 0, root.useShadow);
						}
						
						// changed:
						if(effectMode > 0 && enablePostAndInteractivity)
						{
							root.collectDepthDraws(this, depthRenderer, encDepthMaterial);
						}
						
						// Debug the boundbox
						if (debug && root.boundBox != null && (checkInDebug(root) & Debug.BOUNDS)) Debug.drawBoundBox(this, root.boundBox, root.localToCameraTransform);
					}
					
					// changed: added filter
					if(renderOnly != null && filterObjects)
					{
						filterChildren(root);
					}
					
					// Gather the draws for children
					root.collectChildrenDraws(this, lights, lightsLength, root.useShadow);
					
					// changed:
					if(effectMode > 0 && enablePostAndInteractivity)
					{
						root.collectChildrenDepthDraws(this, depthRenderer, encDepthMaterial);
					}
					
					// changed:
					if(enablePostAndInteractivity)
					{
						// Mouse events processing					
						view.processMouseEvents(context3D, this);
					}
					
					// changed: Set texture as render target
					// Moved after mouse eventsprocessing as somehow setting render to texture breaks mouse event detection
					if(enablePostAndInteractivity && sceneRenderTarget != null)
					{
						context3D.setRenderToTexture(sceneRenderTarget, true);
						context3D.clear();
					}
						
					// Render
					renderer.render(context3D);
					
					// changed:
					// TODO: separate render to texture and in backbuffer in two stages
					if(effectMode > 0 && enablePostAndInteractivity)
					{
						encDepthMaterial.useNormals = effectMode == 3 || effectMode == 8 || effectMode == 9;
						
						// TODO: subpixel accuracy check
						rect.width = Math.ceil(view._width >> (_depthScale + ssaoScale));
						rect.height = Math.ceil(view._height >> (_depthScale + ssaoScale));
						context3D.setScissorRectangle(rect);
						context3D.setRenderToTexture(depthTexture, true, 0, 0);
						if (encDepthMaterial.useNormals) {
							//						context3D.clear(1, 0, 0.5, 0.5);
							context3D.clear(1, 0, -1, 0.5);
						} else {
							context3D.clear(1, 0);
						}
						depthRenderer.render(context3D);
						
						context3D.setScissorRectangle(null);
						
						var visibleTexture:Texture = depthTexture;
						var multiplyEnabled:Boolean = false;
						
						if (effectMode == MODE_SSAO_COLOR || effectMode == MODE_SSAO_ONLY) {
							// Draw ssao
							context3D.setRenderToTexture(ssaoTexture, true, 0, 0);
							context3D.clear(0, 0);
							ssaoAngular.depthScaleX = 1;
							ssaoAngular.depthScaleY = 1;
							ssaoAngular.width = 1 << effectTextureLog2Width;
							ssaoAngular.height = 1 << effectTextureLog2Height;
							ssaoAngular.uToViewX = (1 << (effectTextureLog2Width + ssaoScale));
							ssaoAngular.vToViewY = (1 << (effectTextureLog2Height + ssaoScale));
							ssaoAngular.clipSizeX = view._width/ssaoAngular.uToViewX;
							ssaoAngular.clipSizeY = view._height/ssaoAngular.vToViewY;
							ssaoAngular.depthNormalsTexture = depthTexture;
							ssaoAngular.collectQuadDraw(this);
							renderer.render(context3D);
							
							if (blurEnabled) {
								// Apply blur
								// TODO: draw blur directly to Context3D
								context3D.setRenderToTexture(bluredSSAOTexture, true, 0, 0);
								context3D.clear(0, 0);
								ssaoBlur.width = 1 << effectTextureLog2Width;
								ssaoBlur.height = 1 << effectTextureLog2Height;
								ssaoBlur.clipSizeX = ssaoAngular.clipSizeX;
								ssaoBlur.clipSizeY = ssaoAngular.clipSizeY;
								ssaoBlur.ssaoTexture = ssaoTexture;
								ssaoBlur.collectQuadDraw(this);
								renderer.render(context3D);
							}
							visibleTexture = blurEnabled ? bluredSSAOTexture : ssaoTexture;
							multiplyEnabled = effectMode == 9;
						}						
						
						// changed: Set texture as render target
						// render quad to screen
						if(sceneRenderTarget != null)
						{
							//context3D.setRenderToTexture(sceneRenderTarget, true);	
							//context3D.clear();
						}
						else
						{							
							context3D.setRenderToBackBuffer();
						}
						
						decDepthEffect.multiplyBlend = multiplyEnabled;
						decDepthEffect.scaleX = encDepthMaterial.outputScaleX;
						decDepthEffect.scaleY = encDepthMaterial.outputScaleY;
						decDepthEffect.depthTexture = visibleTexture;
						if (ssaoScale != 0) {
							decDepthEffect.mode = effectMode > 3 ? 4 : effectMode;
						} else {
							decDepthEffect.mode = effectMode > 3 ? 0 : effectMode;
						}
						
						if(effectMode == DEPTH_FOR_CACHE)
						{
							context3D.setRenderToTexture(ssaoTexture);
							context3D.clear();
							decDepthEffect.collectQuadDraw(this);					
							renderer.render(context3D);
						}
					}
				}
				
				if(sceneRenderTarget == null)
				{
					// Output
					if (view._canvas == null) {
						context3D.present();
					} else {
						context3D.drawToBitmapData(view._canvas);
						context3D.present();
					}
				}		
			}
			// Clearing
			lights.length = 0;
			childLights.length = 0;
			occluders.length = 0;
		}
		
		alternativa3d function handleMouse():void
		{
			
		}
		
		/**
		 * Check if objects is present in renderOnly list.
		 */
		private function shouldRender(object:Object3D):Boolean
		{
			var curr:ObjectList = renderOnly;
			
			while(curr != null)
			{
				if(curr.object == object)
				{
					return true;
				}
				
				curr = curr.next;
			}
			
			return false;
		}
		
		/**
		 * Allow render only objects that are in renderOnly list.
		 */
		private function filterChildren(root:Object3D):void
		{
			var curr:Object3D = root.childrenList;
			var levelUp:Boolean = false;
			
			// Traverse object graph (depth-first)
			while(curr != null)
			{
				if(!levelUp)
				{
					if(!shouldRender(curr))
					{
						curr.culling = -1;
					}
				}
				
				// Go one level down
				if(curr.numChildren > 0 && !levelUp)
				{
					curr = curr.childrenList;
				}
					// Go right
				else if(curr.next != null)
				{
					curr = curr.next;
					levelUp = false;
				}
					// Go one level up
				else
				{
					curr = curr.parent;
					levelUp = true;
				}
			}
		}
		
		/*------------------------
		Copied from base
		------------------------*/
		
		static private const stack:Vector.<int> = new Vector.<int>();
		
		private function sortOccluders():void {
			stack[0] = 0;
			stack[1] = occludersLength - 1;
			var index:int = 2;
			while (index > 0) {
				index--;
				var r:int = stack[index];
				var j:int = r;
				index--;
				var l:int = stack[index];
				var i:int = l;
				var occluder:Occluder = occluders[(r + l) >> 1];
				var median:Number = occluder.distance;
				while (i <= j) {
					var left:Occluder = occluders[i];
					while (left.distance < median) {
						i++;
						left = occluders[i];
					}
					var right:Occluder = occluders[j];
					while (right.distance > median) {
						j--;
						right = occluders[j];
					}
					if (i <= j) {
						occluders[i] = right;
						occluders[j] = left;
						i++;
						j--;
					}
				}
				if (l < j) {
					stack[index] = l;
					index++;
					stack[index] = j;
					index++;
				}
				if (i < r) {
					stack[index] = i;
					index++;
					stack[index] = r;
					index++;
				}
			}
		}
		
		private function sortLights(l:int, r:int):void {
			var i:int = l;
			var j:int = r;
			var left:Light3D;
			var index:int = (r + l) >> 1;
			var m:Light3D = lights[index];
			var mid:int = m.type;
			var right:Light3D;
			do {
				while ((left = lights[i]).type < mid) {
					i++;
				}
				while (mid < (right = lights[j]).type) {
					j--;
				}
				if (i <= j) {
					lights[i++] = right;
					lights[j--] = left;
				}
			} while (i <= j);
			if (l < j) {
				sortLights(l, j);
			}
			if (i < r) {
				sortLights(i, r);
			}
		}
	}
}