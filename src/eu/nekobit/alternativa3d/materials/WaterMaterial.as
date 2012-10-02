package eu.nekobit.alternativa3d.materials
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.DrawUnit;
	import alternativa.engine3d.core.Light3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.core.VertexAttributes;
	import alternativa.engine3d.core.View;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.materials.compiler.VariableType;
	import alternativa.engine3d.objects.Mesh;
	import alternativa.engine3d.objects.Surface;
	import alternativa.engine3d.resources.Geometry;
	import eu.nekobit.alternativa3d.resources.RawTextureResource;
	import alternativa.engine3d.resources.TextureResource;
	
	import avmplus.getQualifiedClassName;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.VertexBuffer3D;
	import flash.geom.Matrix3D;
	import flash.geom.Vector3D;
	import flash.utils.Dictionary;
	import flash.utils.getDefinitionByName;
	import flash.utils.getTimer;
	import alternativa.engine3d.materials.A3DUtils;
	import alternativa.engine3d.materials.Material;
	
	use namespace alternativa3d;
	
	/**
	 * Water material.
	 * 
	 * @author Varnius
	 */
	public class WaterMaterial extends Material
	{		
		// Global program cache for this material
		
		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;		
		private var programsCache:Dictionary;
		
		/**
		 * Normal map 1.
		 */
		public var normalMap1:TextureResource;
		
		/**
		 * Normal map 2.
		 */
		public var normalMap2:TextureResource;
		
		alternativa3d var refractionMap:RawTextureResource;
		alternativa3d var reflectionMap:RawTextureResource;	
		
		/**
		 * Enable/disable antialiasing when prerendering.
		 */
		public var useAntiAliasing:Boolean = false;
		
		/**
		 * Prerender texture size.
		 */
		public var prerenderTextureSize:int = 512;
		
		/**
		 * Perturbation amount for refractive map. Higher value means more perturbation.
		 */
		public var perturbRefractiveBy:Number = 0.07;
		
		/**
		 * Perturbation amount for reflective map. Higher value means more perturbation.
		 */
		public var perturbReflectiveBy:Number = 0.21;
		
		/**
		 * Water tint color red value.
		 */
		public var waterColorR:Number = 0;
		
		/**
		 * Water tint color green value.
		 */
		public var waterColorG:Number = 0.15;
		
		/**
		 * Water tint color blue value.
		 */
		public var waterColorB:Number = 0.115;
		
		/**
		 * Water tint amount.
		 */
		public var waterTintAmount:Number = 0;
		
		/**
		 * Fresnel multiplier. Should be in range [0, 1].
		 */
		public var fresnelMultiplier:Number = 1.0;
		
		/**
		 * Reflection (fresnel -  1)  multiplier. Should be in range [0, 1].
		 */
		public var reflectionMultiplier:Number = 0.86;
		
		// UV scroll speed
		
		/**
		 *	Normal 1 uv scroll speed - x axis.
		 */
		public var UVScrollSpeedX1:Number = 0.02;
		
		/**
		 *	Normal 2 uv scroll speed - y axis.
		 */
		public var UVScrollSpeedY1:Number = 0.08;	
		
		/**
		 *	Normal 2 uv scroll speed - x axis.
		 */
		public var UVScrollSpeedX2:Number = 0.01;
		
		/**
		 *	Normal 2 uv scroll speed - y axis.
		 */
		public var UVScrollSpeedY2:Number = 0.04;
		
		// Normal map scale factors
		
		/**
		 *	Normal 1 uv scale factor.
		 */
		public var UVScaleFactor1:Number = 1;
		
		/**
		 *	Normal 2 uv scale factor.
		 */
		public var UVScaleFactor2:Number = 20;		
		
		alternativa3d var refractiveRenderPass:Boolean = false;
		alternativa3d var reflectiveRenderPass:Boolean = false;
		
		private static var zeroVector:Vector3D = new Vector3D();
		private var fresnelCoefs:Vector3D = new Vector3D(0.2, 5, 1 - 0.2);		
		private var pos:Vector3D = new Vector3D();
		private var rCamera:Camera3D;
		private var prevRenderTextureSize:int = 0;	
		private var lastTime:Number = 0;
		private var currOffset1:Vector3D = new Vector3D();
		private var currOffset2:Vector3D = new Vector3D();
		
		/**
		 * Creates a new instance of thismaterial. One instance of this material can be used to generate water only on one object.
		 * The target object should be panar and have a surface normal (in global space) (0,0,1) for all vertices. Call update methods to update material state.
		 * 
		 * @param normalMap Normal map 1.
		 * @param normalMap Normal map 2.
		 */
		public function WaterMaterial(normalMap1:TextureResource, normalMap2:TextureResource)
		{
			super();
						
			this.normalMap1 = normalMap1;
			this.normalMap2 = normalMap2;
		}
		
		/*---------------------------
		Public methods
		---------------------------*/	
		
		/**
		 * Updates water.
		 * 
		 * @param stage3D Instance of Stage3D used for rendering.
		 * @param camera Camera used for rendering.
		 * @param object Object to which this material is applied to.
		 * @param hideFromReflection List of objects to hide when rendering reflection.
		 */
		public function update(stage3D:Stage3D, camera:Camera3D, object:Object3D, hideFromReflection:Vector.<Object3D> = null):void
		{
			if(object == null || camera == null || stage3D == null)
			{
				return;
			}
			
			/*-----------------------
			Prepare render targets
			-----------------------*/
			
			// Create reflection map
			if(refractionMap == null)
			{
				refractionMap = new RawTextureResource();	
				reflectionMap = new RawTextureResource();
			}
			
			// Resize and init reflection map
			if(prevRenderTextureSize != prerenderTextureSize)
			{
				refractionMap.reset(stage3D.context3D, prerenderTextureSize, prerenderTextureSize);
				reflectionMap.reset(stage3D.context3D, prerenderTextureSize, prerenderTextureSize);
			}
			
			prevRenderTextureSize = prerenderTextureSize;
			
			/*-----------------------
			Render refractive map
			-----------------------*/

			stage3D.context3D.setRenderToTexture(refractionMap.texture, true, useAntiAliasing ? camera.view.antiAlias : 0);
			stage3D.context3D.clear();
			
			refractiveRenderPass = true;
			camera.render(stage3D);
			refractiveRenderPass = false;
			
			/*-----------------------
			Render reflective map
			-----------------------*/
			
			// Create reflection camera			
			if(rCamera == null)
			{
				rCamera = new Camera3D(camera.nearClipping, camera.farClipping);
				rCamera.view = new View(camera.view.width, camera.view.height);
				camera.view.stage.addChild(rCamera.view);
				rCamera.view.visible = false;
			}
			
			// Copy properties for reflection camera			
			rCamera.nearClipping = camera.nearClipping;
			rCamera.farClipping = camera.farClipping;
			rCamera.fov = camera.fov;
			rCamera.view.width = camera.view.width;
			rCamera.view.height = camera.view.height;
			rCamera.view.backgroundColor = camera.view.backgroundColor;
			rCamera.view.backgroundAlpha = camera.view.backgroundAlpha;
			camera.parent.addChild(rCamera);			
			
			// Calculate reflection camera position and rotation			
			pos.copyFrom(object.globalToLocal(camera.localToGlobal(new Vector3D())));
			pos.z *= -1;
			
			var pos2:Vector3D = object.localToGlobal(pos);
			pos = camera.parent.globalToLocal(pos2);
			rCamera.setPosition(pos.x, pos.y, pos.z);
			
			// todo: more flexible camera rotation calculation
			rCamera.rotationX = Math.PI - camera.rotationX;
			rCamera.rotationY = camera.rotationY;
			rCamera.rotationZ = camera.rotationZ;	
			
			stage3D.context3D.setRenderToTexture(reflectionMap.texture, true, useAntiAliasing ? camera.view.antiAlias : 0);
			
			reflectiveRenderPass = true;	
			
			for each(var o:Object3D in hideFromReflection)
			{
				o.visible = false;
			}
			
			rCamera.render(stage3D);
			
			for each(o in hideFromReflection)
			{
				o.visible = true;
			}
			
			reflectiveRenderPass = false;
			
			// Set render mode back to normal
			stage3D.context3D.setRenderToBackBuffer();		
			
			/*-----------------------
			Handle texture animation
			-----------------------*/
			
			// Calculate UV offset for bump maps
			var timeNow:uint = getTimer();
			var timeDelta:Number = (timeNow - lastTime) / 1000;
			
			currOffset1.x += UVScrollSpeedX1 * timeDelta;
			currOffset1.y += UVScrollSpeedY1 * timeDelta;
			
			currOffset2.x += UVScrollSpeedX2 * timeDelta;
			currOffset2.y += UVScrollSpeedY2 * timeDelta;
			
			// Offset 1
			if(Math.abs(currOffset1.x) > UVScaleFactor1)
				currOffset1.x = 0;			
			if(Math.abs(currOffset1.y) > UVScaleFactor1)
				currOffset1.y = 0;
			
			// Offset 2
			if(Math.abs(currOffset2.x) > UVScaleFactor2)
				currOffset2.x = 0;			
			if(Math.abs(currOffset2.y) > UVScaleFactor2)
				currOffset2.y = 0;		
			
			lastTime = timeNow;			
		}
		
		/*---------------------------
		Collect draws
		---------------------------*/
		
		/**
		 * @private
		 * Collect draws.
		 * 
		 * @param camera Current camera.
		 * @param surface Current surface.
		 * @param geometry Current geometry.
		 * @param lights List of lights.
		 * @param lightsLength Number of lights.
		 * @param useShadows Indicates whether to use shadows.
		 * @param objectRenderPriority Render priority of current object.
		 */
		override alternativa3d function collectDraws(camera:Camera3D, 
													 surface:Surface, 
													 geometry:Geometry,
													 lights:Vector.<Light3D>, 
													 lightsLength:int,
													 useShadow:Boolean, 
													 objectRenderPriority:int = -1):void
		{			
			if(refractionMap == null || refractionMap._texture == null || reflectionMap == null || reflectionMap._texture == null || normalMap1 == null || normalMap1._texture == null || normalMap2 == null || normalMap2._texture == null)
			{
				return;
			}
			
			// Do not draw self when rendering reflection
			if(reflectiveRenderPass)
			{
				return;
			}
			
			// Set buffers
			var positionBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);
			
			if(positionBuffer == null || uvBuffer == null)
			{
				return;
			}
			
			// Owner object of current surface
			var object:Object3D = surface.object;
			
			/*-------------------
			Handle shader
			program cache
			-------------------*/
			
			// Refresh programs for this context.
			if(camera.context3D != cachedContext3D)
			{
				cachedContext3D = camera.context3D;
				programsCache = caches[cachedContext3D];
				
				if(programsCache == null)
				{
					programsCache = new Dictionary();
					caches[cachedContext3D] = programsCache;
				}
			}
			
			var optionsPrograms:Dictionary = programsCache[object.transformProcedure];
			
			if(optionsPrograms == null)
			{
				optionsPrograms = new Dictionary(false);
				programsCache[object.transformProcedure] = optionsPrograms;
			}		
			
			/*-------------------
			Get shader 
			programs/drawUnit
			-------------------*/
			
			var program:WaterMaterialProgram;
			
			program = getProgram(object, optionsPrograms, camera);
			
			// Refractive prerender pass
			if(refractiveRenderPass)
			{
				createDrawUnitPrerender(program, camera, surface, geometry, objectRenderPriority);
			}
			// Final render pass
			else
			{
				createDrawUnitFinal(program, camera, surface, geometry, objectRenderPriority);
			}			
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		/**
		 * @private
		 * Fill resources.
		 * 
		 * @param resources Resource dictionary.
		 * @param resourceType Type of resource.
		 */
		override alternativa3d function fillResources(resources:Dictionary, resourceType:Class):void
		{
			super.fillResources(resources, resourceType);
			
			if(refractionMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(refractionMap)) as Class, resourceType))
			{
				resources[refractionMap] = true;
			}
			
			if(reflectionMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(reflectionMap)) as Class, resourceType))
			{
				resources[reflectionMap] = true;
			}
			
			if(normalMap1 != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(normalMap1)) as Class, resourceType))
			{
				resources[normalMap1] = true;
			}
			
			if(normalMap2 != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(normalMap1)) as Class, resourceType))
			{
				resources[normalMap2] = true;
			}
		}
		
		/**
		 * Create material program.
		 */
		private function getProgram(object:Object3D, 
									programs:Dictionary,
									camera:Camera3D
		):WaterMaterialProgram
		{
			var key:String = refractiveRenderPass ? "reflectivePass1" : "reflectivePass2";
			var program:WaterMaterialProgram = programs[key];
			
			if(program == null)
			{
				var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
				var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);				
				var positionVar:String = "aPosition";
				
				/*---------------------
				Vertex
				---------------------*/
				
				vertexLinker.declareVariable(positionVar, VariableType.ATTRIBUTE);
				
				if(object.transformProcedure != null)
				{
					positionVar = appendPositionTransformProcedure(object.transformProcedure, vertexLinker);
				}
				
				vertexProcedure.assignVariableName(VariableType.CONSTANT, 0, "cWorldViewProjMatrix", 4);
				
				// Prerender pass
				if(refractiveRenderPass)
				{
					// Vertex
					vertexLinker.addProcedure(prerenderVertexProcedure);
					vertexLinker.setInputParams(prerenderVertexProcedure, positionVar);
					
					// Fragment
					fragmentLinker.addProcedure(prerenderFragmentProcedure);
					fragmentLinker.declareVariable("cColor", VariableType.CONSTANT);
				}
					// Final render pass
				else
				{
					vertexLinker.addProcedure(vertexProcedure);
					vertexLinker.setInputParams(vertexProcedure, positionVar);
					fragmentLinker.addProcedure(fragmentProcedure);
				}			
				
				fragmentLinker.varyings = vertexLinker.varyings;
				program = new WaterMaterialProgram(vertexLinker, fragmentLinker);	
				
				program.upload(camera.context3D);
				programs[key] = program;
			}
			
			return program;
		}
		
		/**
		 * Gets drawUnit for final render.
		 */
		private function createDrawUnitFinal(program:WaterMaterialProgram,
											 camera:Camera3D,
											 surface:Surface,
											 geometry:Geometry,
											 objectRenderPriority:int):void 
		{
			// Get buffers
			var positionBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);
			
			if(positionBuffer == null || uvBuffer == null)
			{
				return;
			}
			
			var object:Object3D = surface.object;
			var cameraPos:Vector3D = camera.localToGlobal(zeroVector);
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(object, program.program, geometry._indexBuffer, surface.indexBegin, surface.numTriangles, program);
			
			// Get first normal of the mesh and transform it to world space
			var geometry:Geometry = (object as Mesh).geometry;
			var normals:Vector.<Number> = geometry.getAttributeValues(VertexAttributes.NORMAL);
			var normal:Vector3D = new Vector3D(normals[0], normals[1], normals[2]);
			var normalTransform:Matrix3D = object.matrix.clone();
			normalTransform.invert();
			normalTransform.transpose();
			normal = normalTransform.transformVector(normal);
			//normal.normalize();
			
			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, geometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(program.aNormalMapUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set vertex constants
			
			// Set transform consts
			object.setTransformConstants(drawUnit, surface, program.vertexShader, camera);
			// Set WVP matrix
			drawUnit.setProjectionConstants(camera, program.cWorldViewProjMatrix, object.localToCameraTransform);
			// Set world matrix
			drawUnit.setVertexConstantsFromTransform(program.cWorldMatrix, object.localToGlobalTransform);
			// Set bump offset (#1, #2)
			drawUnit.setVertexConstantsFromNumbers(program.cBumpOffset12, currOffset1.x, currOffset1.y, currOffset2.x, currOffset2.y);
			// Set bump scale factors (#1, #2, #3, #4)
			drawUnit.setVertexConstantsFromNumbers(program.cBumpScaleFactors1234, UVScaleFactor1, UVScaleFactor2, 0, 0);
			
			// Set fragment constants
			
			// Value w is used only for storing constant 1
			drawUnit.setFragmentConstantsFromNumbers(program.cRefractiveCoefs, 0.5, -0.5, 0.5, 1);
			// Value w is used only for storing constant 1
			drawUnit.setFragmentConstantsFromNumbers(program.cReflectiveCoefs, 0.5, 0.5, 0.5, 1);
			// Perturbation amount for refractive map, x used for storing constant 2
			drawUnit.setFragmentConstantsFromNumbers(program.cPerturbRefractive, 2, 0, 0, perturbRefractiveBy);
			// Perturbation amount for reflective map, x used for storing constant 2
			drawUnit.setFragmentConstantsFromNumbers(program.cPerturbReflective, 2, 0, 0, perturbReflectiveBy);
			// Fresnel coefs
			drawUnit.setFragmentConstantsFromNumbers(program.cFresnelCoefs, fresnelCoefs.x, fresnelCoefs.y, fresnelCoefs.z, 0);
			// Set camera position const
			drawUnit.setFragmentConstantsFromNumbers(program.cCameraPos, cameraPos.x, cameraPos.y, cameraPos.z, 0);
			// Fresnel multiplier
			drawUnit.setFragmentConstantsFromNumbers(program.cFresnelMultiplier, fresnelMultiplier, 0, 0, 0);
			// Set calculated surface normal
			drawUnit.setFragmentConstantsFromNumbers(program.cNormal, normal.x, normal.y, normal.z, 0);		
			// Set reflection multiplier
			drawUnit.setFragmentConstantsFromNumbers(program.cReflectionMultiplier, reflectionMultiplier, 0, 0, 0);	
			// Set number of bump maps
			drawUnit.setFragmentConstantsFromNumbers(program.cNumBumpMaps, 2, 0, 0, 0);
			// Set water tint color
			drawUnit.setFragmentConstantsFromNumbers(program.cWaterTintColor, waterColorR * waterTintAmount, waterColorG * waterTintAmount, waterColorB * waterTintAmount, 0);
			// Set water tint amount
			drawUnit.setFragmentConstantsFromNumbers(program.cWaterTintAmount, waterTintAmount, 0, 0, 1 - waterTintAmount);
			
			// Set samplers
			
			drawUnit.setTextureAt(program.sRefractionMap, refractionMap._texture);
			drawUnit.setTextureAt(program.sReflectionMap, reflectionMap._texture);
			drawUnit.setTextureAt(program.sNormalMap1, normalMap1._texture);
			drawUnit.setTextureAt(program.sNormalMap2, normalMap2._texture);
			
			// Setup blending
			
			drawUnit.blendSource = Context3DBlendFactor.SOURCE_ALPHA;
			drawUnit.blendDestination = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;			
			camera.renderer.addDrawUnit(drawUnit, objectRenderPriority >= 0 ? objectRenderPriority : Renderer.OPAQUE);
		}
		
		/**
		 * Gets drawUnit for prerender.
		 */
		private function createDrawUnitPrerender(program:WaterMaterialProgram,
												 camera:Camera3D,
												 surface:Surface,
												 geometry:Geometry,
												 objectRenderPriority:int):void 
		{
			// Get buffers
			var positionBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.POSITION);
			
			if(positionBuffer == null)
			{
				return;
			}
			
			var object:Object3D = surface.object;
			
			// Create draw unit
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(object, program.program, geometry._indexBuffer, surface.indexBegin, surface.numTriangles, program);
			
			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, geometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			
			// Set constants
			object.setTransformConstants(drawUnit, surface, program.vertexShader, camera);
			drawUnit.setProjectionConstants(camera, program.cWorldViewProjMatrix, object.localToCameraTransform);	
			// Leave destination color intact but make alpha mask for this refractive object (used later to get rid of artifacts)
			drawUnit.setFragmentConstantsFromNumbers(program.cColor, 1, 1, 1, 0);
			
			// Set samplers
			// ..
			
			// Blending mode that results in: dest.rgba * (1,1,1,0)
			drawUnit.blendSource = Context3DBlendFactor.ZERO;
			drawUnit.blendDestination = Context3DBlendFactor.SOURCE_COLOR;
			camera.renderer.addDrawUnit(drawUnit, objectRenderPriority >= 0 ? objectRenderPriority : Renderer.OPAQUE);
		}
		
		/*---------------------------
		Vertex procedures
		---------------------------*/
		
		/**
		 * @private
		 */
		static alternativa3d const prerenderVertexProcedure:Procedure = new Procedure(
			[
				// Declarations
				"#a0=aPosition",			
				"#c0=cWorldViewProjMatrix",
				
				// Multiply by MVP matrix
				"m44 t0 a0 c0",
				// Set transformed vertex position as output
				"mov o0 t0"
			], "vertexProcedure");
		
		/**
		 * @private
		 */
		static alternativa3d const vertexProcedure:Procedure = new Procedure(
			[
				// Declarations
				"#a0=aPosition",			
				"#a1=aNormalMapUV",
				"#c0=cWorldViewProjMatrix",
				"#c1=cBumpOffset12",
				"#c2=cBumpScaleFactors1234",
				"#c3=cWorldMatrix",				
				"#v0=vPosition",
				"#v1=vNormalMapUV",
				"#v2=vWorldPos",
				"#v3=vNormalMapUV2",				
				
				// Multiply by MVP matrix
				"m44 t0 a0 c0",
				// Move transformed vertex position to varying-0
				"mov v0 t0",
				
				// Offset/scale normal map UV coords #1, move to v1
				"mov t1 a1",
				"div t1.xyxy t1.xyxy c2.xxxx",
				"add t1.xy t1.xy c1.xy",
				"mov v1 t1",
				
				// Offset/scale normal map UV coords #2, move to v3
				"mov t1 a1",
				"div t1.xyxy t1.xyxy c2.yyyy",
				"add t1.xy t1.xy c1.zw",
				"mov v3 t1",
				
				// Offset/scale normal map UV coords #3, move to v4
				// Offset/scale normal map UV coords #4, move to v5
				// .. not used currently
				
				// Transform vertex pos to world space and move into varying-2
				"m44 v2 a0 c3",
				// Set transformed vertex position as output
				"mov o0 t0"
			], "vertexProcedure");
		
		/*---------------------------
		Fragment procedures
		---------------------------*/
		
		/**
		 * @private
		 */
		static alternativa3d const prerenderFragmentProcedure:Procedure = new Procedure(
			[
				"#c0=cColor",
				
				// Just return black alpha mask with alpha = 0 for this material at prerender
				"mov o0, c0"
			], "fragmentProcedure");
		
		/**
		 * @private
		 */
		static alternativa3d const fragmentProcedure:Procedure = new Procedure(
			[
				// Declarations
				"#s0=sRefractionMap",
				"#s1=sReflectionMap",
				"#s2=sNormalMap1",
				"#s3=sNormalMap2",
				"#c0=cRefractiveCoefs",
				"#c1=cReflectiveCoefs",
				"#c2=cPerturbRefractive",
				"#c3=cPerturbReflective",			
				"#c4=cFresnelCoefs",
				"#c5=cCameraPos",
				"#c6=cFresnelMultiplier",
				"#c7=cNormal",
				"#c8=cReflectionMultiplier",
				"#c9=cNumBumpMaps",
				"#c10=cWaterTintColor",
				"#c11=cWaterTintAmount",
				"#v0=vPosition",			
				"#v1=vNormalMapUV",
				"#v2=vWorldPos",
				"#v3=vNormalMapUV2",				
				
				// Perspective divide
				"div t0.xy v0.xy v0.ww",
				
				// --- Sample bump maps ---
				
				// Save NDC coord for calculating reflection map uv coord later
				"mov t7.xy t0.xy",
				// Unpack to [0, 1] (vPos * 0.5 + 0.5)
				// Bug with multiplying both (xy xy) at the same time
				"mul t0.zwzw t0.xyxy c0.xyxy",
				"add t0.xy t0.zw c0.zz",			
				// Sample normal map #1 at interpolated position
				"tex t1,v1,s2 <2d,repeat,linear>",
				// Sample normal map #2 at interpolated position
				"tex t2,v3,s3 <2d,repeat,linear>",
				
				// Add up all normal values
				"add t1.xyz t1.xyz t2.xyz",
				
				// Unpack normal xy values to [-1, 1] to add refraction map perturbations evenly and avoid artifacts
				// finalNormal = normalize(2 * (n1 + n2 ... + nm) - numNormalMaps);
				// 2 *
				"mul t1.xyxy t1.xyxy c2.xxxx",				
				// - cNumBumpMaps
				"sub t1.xy t1.xy c9.x",
				// Normalize summed unpacked normals
				"nrm t1.xyz t1.xyz",
				// Save unpacked unscaled normal val for later
				"mov t5.xyzw t1.xyzw",
				// Scale normal map xy components
				"mul t1.x t1.x c2.w",
				"mul t1.y t1.y c2.w",
				// Sample refraction map at unperturbed UV coords (used in case perturbed ones produce artifacts)
				"tex t2,t0,s0 <2d,clamp,linear>",
				// Perturb calculated refraction map UV coords by normal
				"add t0.xy t0.xy t1.xy", 
				// Sample refraction map at perturbed UV coords
				"tex t1,t0,s0 <2d,clamp,linear>",				
				
				// --- Handle refractions ---
				
				// Choose which sample to use
				// unperturbed * perturbedAlpha
				"mul t2.xyzw t2.xyzw t1.wwww",
				// 1 - perturbedAlpha
				"sub t3.w c0.w t1.w",
				// perturbed * (1 - perturbedAlpha)
				"mul t3.xyzw t1.xyzw t3.wwww",
				// Final color of reflection map
				"add t2 t2 t3",
				// Reset refraction map alpha to 1
				"mov t2.w c0.w",
				
				// --- Tint refraction ---
				
				// Multiply refraction color by (1 - tintAmount)
				"mul t2.xyz t2.xyz c11.w",
				// Add up multiplier refraction and tint colors
				"add t2.xyz t2.xyz c10.xyz",
				
				// --- Handle reflections ---
				
				// Move saved NDC coord from t7
				"mov t0.xy t7.xy",
				// Unpack to [0, 1] (vPos * 0.5 + 0.5)
				// Bug with multiplying both (xy xy) at the same time
				"mul t0.z t0.x c1.x",
				"mul t0.w t0.y c1.y",
				"add t0.xy t0.zw c1.zz",
				// Move saved unperturbed normal from t5
				"mov t1.xyz t5.xyz",
				// Perturb normal map xy components
				"mul t1.x t1.x c3.w",
				"mul t1.y t1.y c3.w",
				// Save perturbed normal for later Fresnel term calculations
				"mov t3.xyz t1.xyz",
				// Perturb calculated reflection map UV coords by normal
				"add t0.xy t0.xy t1.xy",				
				// Sample reflection map at perturbed position
				"tex t1,t0,s1 <2d,clamp,linear>",
				// Reset reflection map alpha to 1
				"mov t1.w c0.w",
				
				// --- Calculate angle between normal and eye vector ---
				
				// So, we have refractive color in t2 and reflective map color in t1
				// Time to blend those!
				
				// Calculate eye vector from (c5 - cameraPos in world space, v2 - vertex pos in world space)
				"sub t6.xyz c5.xyz v2.xyz",
				"nrm t6.xyz t6.xyz",
				
				// --- Calculate Fresnel term ---
				
				// Calculate dot product between eye vector in world space and surface normal vector in world space
				"dp3 t0.x t6.xyz c7.xyz",
				// max(dot(eyeVec, normal), 0)
				"max t0.x t0.x c2.y",
				// 1 - max(dot(eyeVec, normal), 0)
				"sub t3.x c0.w t0.x",				
				// Calculate Fresnel term
				"pow t0.x t3.x c4.y",
				"mul t0.x t0.x c4.z",
				"add t0.x t0.x c4.x",
				"max t0.x t0.x c2.y",
				// Multiply Fresnel val by cFresnelMultiplier
				"mul t0.x t0.x c6.x",
				
				// --- Blend colors ---
				
				// Tmp used now: t0-fresnel t1-refl t2-refr t3-facing				
				// color = refractiveColor * (1 - fresnelTerm) + reflectiveColor * (fresnelTerm);
				"sub t3.x c0.w t0.x",
				
				// Reflection coef - adds up to Fresnel val to increase amount of reflection
				"mul t4.x t3.x c8.x",
				"add t0.x t0.x t4.x",
				
				// Re-evaluate 1 - Fresnel
				"sub t3.x c0.w t0.x",
				
				"mul t1.xyz t1.xyz t0.x",
				"mul t2.xyz t2.xyz t3.x",
				"add t1.xyz t1.xyz t2.xyz",
				
				// Reset alpha to 1
				"mov t1.w c0.w",
				
				"mov o0, t1"
			], "fragmentProcedure");
	}
}

import alternativa.engine3d.materials.ShaderProgram;
import alternativa.engine3d.materials.compiler.Linker;

import flash.display3D.Context3D;

class WaterMaterialProgram extends ShaderProgram
{	
	// Vertex
	public var aPosition:int = -1;
	public var aNormalMapUV:int = -1;
	public var cWorldViewProjMatrix:int = -1;
	public var cWorldMatrix:int = -1;
	public var cBumpOffset12:int = -1;
	public var cBumpScaleFactors1234:int = -1;
	
	// Fragment
	public var cRefractionAmount:int = -1;
	public var sDiffuseMap:int = -1;
	public var sRefractionMap:int = -1;
	public var sReflectionMap:int = -1;
	public var sNormalMap1:int = -1;
	public var sNormalMap2:int = -1;
	public var cRefractiveCoefs:int = -1;
	public var cReflectiveCoefs:int = -1;
	public var cPerturbRefractive:int = -1;
	public var cPerturbReflective:int = -1;
	public var cFresnelCoefs:int = -1;
	public var cCameraPos:int = -1;
	public var cFresnelMultiplier:int = -1;
	public var cNormal:int = -1;
	public var cReflectionMultiplier:int = -1;
	public var cNumBumpMaps:int = -1;
	public var cWaterTintColor:int = -1;
	public var cWaterTintAmount:int = -1;
	
	// Fragment - refraction prerender
	public var cColor:int = -1;
	
	public function WaterMaterialProgram(vertex:Linker, fragment:Linker)
	{
		super(vertex, fragment);
	}
	
	override public function upload(context3D:Context3D):void
	{
		super.upload(context3D);
		
		// Vertex shader
		aPosition = vertexShader.findVariable("aPosition");
		aNormalMapUV = vertexShader.findVariable("aNormalMapUV");
		cWorldViewProjMatrix = vertexShader.findVariable("cWorldViewProjMatrix");	
		cWorldMatrix = vertexShader.findVariable("cWorldMatrix");
		cBumpOffset12 = vertexShader.findVariable("cBumpOffset12");
		cBumpScaleFactors1234 = vertexShader.findVariable("cBumpScaleFactors1234");
		
		// Fragment shader
		sRefractionMap = fragmentShader.findVariable("sRefractionMap");
		sReflectionMap = fragmentShader.findVariable("sReflectionMap");
		sNormalMap1 = fragmentShader.findVariable("sNormalMap1");
		sNormalMap2 = fragmentShader.findVariable("sNormalMap2");
		cRefractiveCoefs = fragmentShader.findVariable("cRefractiveCoefs");
		cReflectiveCoefs = fragmentShader.findVariable("cReflectiveCoefs");
		cPerturbRefractive = fragmentShader.findVariable("cPerturbRefractive");
		cPerturbReflective = fragmentShader.findVariable("cPerturbReflective");
		cFresnelCoefs = fragmentShader.findVariable("cFresnelCoefs");
		cCameraPos = fragmentShader.findVariable("cCameraPos");
		cFresnelMultiplier = fragmentShader.findVariable("cFresnelMultiplier");
		cNormal = fragmentShader.findVariable("cNormal");
		cReflectionMultiplier = fragmentShader.findVariable("cReflectionMultiplier");
		cNumBumpMaps = fragmentShader.findVariable("cNumBumpMaps");
		cWaterTintColor = fragmentShader.findVariable("cWaterTintColor");
		cWaterTintAmount = fragmentShader.findVariable("cWaterTintAmount");
		
		// Fragment shader - refraction prerender
		cColor = fragmentShader.findVariable("cColor");
	}	
}