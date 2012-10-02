package eu.nekobit.alternativa3d.materials
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.DrawUnit;
	import alternativa.engine3d.core.Light3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.core.VertexAttributes;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.materials.compiler.VariableType;
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
	import flash.utils.Dictionary;
	import flash.utils.getDefinitionByName;
	import alternativa.engine3d.materials.A3DUtils;
	import alternativa.engine3d.materials.Material;
	
	use namespace alternativa3d;
	
	/**
	 * Refractive material.
	 * 
	 * @author Varnius
	 */
	public class RefractiveMaterial extends Material
	{		
		// Global program cache for this material
		
		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;		
		private var programsCache:Dictionary;
		
		/**
		 * Diffuse map.
		 */
		public var diffuseMap:TextureResource;
		
		/**
		 * Normal map.
		 */
		public var normalMap:TextureResource;	
		
		alternativa3d var refractionMap:RawTextureResource;
		
		/**
		 * Refraction amount in range [0, 1]. Used to mix refraction and diffuse maps.
		 */		
		public var refractionAmount:Number;
		
		/**
		 * Enable/disable antialiasing when prerendering.
		 */
		public var useAntiAliasing:Boolean = false;
		
		/**
		 * Prerender texture size.
		 */
		public var prerenderTextureSize:int = 512;
		
		/**
		 * Normal map perturbation amount. Higher means more perturbation.
		 */
		public var perturbRefractionBy:Number = 0.05;
		
		alternativa3d var refractiveRenderPass:Boolean = false;
		
		/**
		 * Class constructor. One instance of this material can be used to generate refraction effect on a number of different
		 * objects but only if all of them are rendered through same camera. Call the update method to update refraction.
		 * 
		 * @param diffuseMap Diffuse map.
		 * @param normalMap Normal map for surface.
		 * @param refractionAmount Refraction amount in range [0, 1]. Used to mix refraction and diffuse maps.
		 */
		public function RefractiveMaterial(diffuseMap:TextureResource, normalMap:TextureResource, refractionAmount:Number = 1)
		{
			super();
			
			this.diffuseMap = diffuseMap;			
			this.normalMap = normalMap;
			this.refractionAmount = refractionAmount;
		}
		
		/*---------------------------
		Public methods
		---------------------------*/
		
		private var prevReflectionTextureSize:int = 0;
		
		/**
		 * Updates reflection.
		 * 
		 * @param stage3D Instance of Stage3D used for rendering.
		 * @param camera Camera used for rendering.
		 * @param object Object to which this material is applied to.
		 */
		public function update(stage3D:Stage3D, camera:Camera3D, object:Object3D):void
		{
			if(object == null || camera == null || stage3D == null)
			{
				return;
			}
			
			// Create reflection map
			if(refractionMap == null)
			{
				refractionMap = new RawTextureResource();				
			}
			
			// Resize and init reflection map
			if(prevReflectionTextureSize != prerenderTextureSize)
			{
				refractionMap.reset(stage3D.context3D, prerenderTextureSize, prerenderTextureSize);
			}
			
			prevReflectionTextureSize = prerenderTextureSize;
			
			// Render refractive map
			stage3D.context3D.setRenderToTexture(refractionMap.texture, true, useAntiAliasing ? camera.view.antiAlias : 0);
			stage3D.context3D.clear();
			
			refractiveRenderPass = true;
			camera.render(stage3D);
			refractiveRenderPass = false;
			
			stage3D.context3D.setRenderToBackBuffer();			
		}
		
		/*---------------------------
		Collect draws
		---------------------------*/
		
		/**
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
			
			if(diffuseMap == null || diffuseMap._texture == null || refractionMap == null || refractionMap._texture == null || normalMap == null || normalMap._texture == null)
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
			
			var program:RefractiveMaterialProgram;
			
			program = getProgram(object, optionsPrograms, camera);
			
			// Prerender pass
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
		 * Fill resources.
		 * 
		 * @param resources Resource dictionary.
		 * @param resourceType Type of resource.
		 */
		override alternativa3d function fillResources(resources:Dictionary, resourceType:Class):void
		{
			super.fillResources(resources, resourceType);
			
			if(diffuseMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(diffuseMap)) as Class, resourceType))
			{
				resources[diffuseMap] = true;
			}
			
			if(refractionMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(refractionMap)) as Class, resourceType))
			{
				resources[refractionMap] = true;
			}
			
			if(normalMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(normalMap)) as Class, resourceType))
			{
				resources[normalMap] = true;
			}
		}
		
		/**
		 * Create material program.
		 */
		private function getProgram(object:Object3D, 
									programs:Dictionary,
									camera:Camera3D
		):RefractiveMaterialProgram
		{
			var key:String = refractiveRenderPass ? "refractivePass1" : "refractivePass2";
			var program:RefractiveMaterialProgram = programs[key];
			
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
					// Vertex
					vertexLinker.declareVariable("aDiffuseUV", VariableType.ATTRIBUTE);	
					vertexLinker.addProcedure(vertexProcedure);
					vertexLinker.setInputParams(vertexProcedure, positionVar);
					
					// Fragment
					fragmentLinker.addProcedure(fragmentProcedure);
					fragmentLinker.declareVariable("cRefractiveCoefs", VariableType.CONSTANT);				
					fragmentLinker.declareVariable("cRefractionAmount", VariableType.CONSTANT);	
					fragmentLinker.declareVariable("cPerturb", VariableType.CONSTANT);
				}			
				
				fragmentLinker.varyings = vertexLinker.varyings;
				program = new RefractiveMaterialProgram(vertexLinker, fragmentLinker);	
					
				program.upload(camera.context3D);
				programs[key] = program;
			}
			
			return program;
		}
		
		/**
		 * Gets drawUnit for final render.
		 */
		private function createDrawUnitFinal(program:RefractiveMaterialProgram,
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
			
			// Create draw unit
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(object, program.program, geometry._indexBuffer, surface.indexBegin, surface.numTriangles, program);

			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, geometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(program.aDiffuseUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set constants
			object.setTransformConstants(drawUnit, surface, program.vertexShader, camera);
			drawUnit.setProjectionConstants(camera, program.cWorldViewProjMatrix, object.localToCameraTransform);	
			// Value w is used only for storing constant 1
			drawUnit.setFragmentConstantsFromNumbers(program.cRefractiveCoefs, 0.5, -0.5, 0.5, 1);
			// Pass reflection amount and inverted reflection amount
			drawUnit.setFragmentConstantsFromNumbers(program.cRefractionAmount, 1 - refractionAmount, 0, 0, refractionAmount);
			drawUnit.setFragmentConstantsFromNumbers(program.cPerturb, 2, 0, 0, perturbRefractionBy);
			
			// Set samplers
			drawUnit.setTextureAt(program.sRefractionMap, refractionMap._texture);
			drawUnit.setTextureAt(program.sDiffuseMap, diffuseMap._texture);
			drawUnit.setTextureAt(program.sNormalMap, normalMap._texture);
			
			drawUnit.blendSource = Context3DBlendFactor.SOURCE_ALPHA;
			drawUnit.blendDestination = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;			
			camera.renderer.addDrawUnit(drawUnit, objectRenderPriority >= 0 ? objectRenderPriority : Renderer.OPAQUE);
		}
		
		/**
		 * Gets drawUnit for prerender.
		 */
		private function createDrawUnitPrerender(program:RefractiveMaterialProgram,
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
		
		static alternativa3d const vertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aDiffuseUV",
			"#c0=cWorldViewProjMatrix",
			"#v0=vPosition",
			"#v1=vDiffuseUV",
			
			// Multiply by MVP matrix
			"m44 t0 a0 c0",
			// Move transformed vertex position to varying-0
			"mov v0, t0",
			// Move diffuse UV coords to varying-1
			"mov v1, a1",
			// Set transformed vertex position as output
			"mov o0 t0"
		], "vertexProcedure");
		
		/*---------------------------
		Fragment procedures
		---------------------------*/
		
		static alternativa3d const prerenderFragmentProcedure:Procedure = new Procedure(
		[
			"#c0=cColor",
			
			// Just return black alpha mask with alpha = 0 for this material at prerender
			"mov o0, c0"
		], "fragmentProcedure");
		
		static alternativa3d const fragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sRefractionMap",
			"#s1=sDiffuseMap",
			"#s2=sNormalMap",
			"#c0=cRefractiveCoefs",
			"#c1=cRefractionAmount",
			"#c2=cPerturb",
			"#v0=vPosition",			
			"#v1=vDiffuseUV",
			
			// Perspective divide
			"div t0.xy v0.xy v0.ww",
			// Unpack to [0, 1] (vPos * 0.5 + 0.5)
			// Bug with multiplying both (xy xy) at the same time
			"mul t0.z t0.x c0.x",
			"mul t0.w t0.y c0.y",
			"add t0.xy t0.zw c0.zz",			
			// Sample normal map at interpolated position
			"tex t1,v1,s2 <2d,repeat,linear>",
			
			// --- Unpack, perturb normals ---
			
			// Unpack normal xy values to [-1, 1] to add refraction map perturbations evenly and avoid artifacts
			"mul t1.x t1.x c2.x",
			"mul t1.y t1.y c2.x",
			"sub t1.xy t1.xy c0.ww",			
			//Perturb normal map xy components
			"mul t1.x t1.x c2.w",
			"mul t1.y t1.y c2.w",
			
			// --- Sample using perturbed coords ---			
			
			// Sample refraction map at unperturbed UV coords (used in case perturbed ones produce artifacts)
			"tex t2,t0,s0 <2d,clamp,linear>",
			// Perturb calculated refraction map UV coords by normal
			"add t0.xy t0.xy t1.xy", 
			// Sample refraction map at perturbed UV coords
			"tex t1,t0,s0 <2d,clamp,linear>",			
			// Choose which sample to use
			// unperturbed * perturbedAlpha
			"mul t2.xyzw t2.xyzw t1.wwww",
			// 1 - perturbedAlpha
			"sub t3.w c0.w t1.w",
			// perturbed * (1 - perturbedAlpha)
			"mul t3.xyzw t1.xyzw t3.wwww",
			// Final color of reflection map
			"add t2 t2 t3",		
			
			// --- Blend diffuse and reflection maps ---
			
			// Sample diffuse map at interpolated position
			"tex t3,v1,s1 <2d,repeat,linear>",			
			// Reset rendered refraction map alpha to 1
			"mov t2.w c0.w",
			// Multiply reflection map value by reflectionAmount
			"mul t2.xyz, t2.xyz, c1.w",
			// Multiply diffuse map value by 1 - reflectionAmount
			"mul t3.xyz t3.xyz c1.x",
			// Add up diffuse and reflection map sampled colors
			"add t2.xyz t2.xyz t3.xyz",
			// Set final output color for current pixel
			"mov o0, t2"
		], "fragmentProcedure");
	}
}

import alternativa.engine3d.materials.ShaderProgram;
import alternativa.engine3d.materials.compiler.Linker;

import flash.display3D.Context3D;

class RefractiveMaterialProgram extends ShaderProgram
{	
	// Vertex
	public var aPosition:int = -1;
	public var aDiffuseUV:int = -1;
	public var cWorldViewProjMatrix:int = -1;
	
	// Fragment
	public var cRefractionAmount:int = -1;
	public var sDiffuseMap:int = -1;
	public var sRefractionMap:int = -1;
	public var sNormalMap:int = -1;
	public var cRefractiveCoefs:int = -1;
	public var cPerturb:int = -1;
	
	// Fragment - prerender
	public var cColor:int = -1;
	
	public function RefractiveMaterialProgram(vertex:Linker, fragment:Linker)
	{
		super(vertex, fragment);
	}
	
	override public function upload(context3D:Context3D):void
	{
		super.upload(context3D);
		
		// Vertex shader
		aPosition = vertexShader.findVariable("aPosition");
		aDiffuseUV = vertexShader.findVariable("aDiffuseUV");
		cWorldViewProjMatrix = vertexShader.findVariable("cWorldViewProjMatrix");	
		
		// Fragment shader
		cRefractionAmount = fragmentShader.findVariable("cRefractionAmount");
		sDiffuseMap = fragmentShader.findVariable("sDiffuseMap");
		sRefractionMap = fragmentShader.findVariable("sRefractionMap");	
		sNormalMap = fragmentShader.findVariable("sNormalMap");
		cRefractiveCoefs = fragmentShader.findVariable("cRefractiveCoefs");
		cPerturb = fragmentShader.findVariable("cPerturb");
		
		// Fragment shader - prerender
		cColor = fragmentShader.findVariable("cColor");
	}	
}