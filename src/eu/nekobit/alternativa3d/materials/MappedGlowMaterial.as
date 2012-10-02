package eu.nekobit.alternativa3d.materials
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.DrawUnit;
	import eu.nekobit.alternativa3d.core.renderers.MappedGlowRenderer;
	import alternativa.engine3d.core.Light3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.core.VertexAttributes;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.materials.compiler.VariableType;
	import alternativa.engine3d.objects.Surface;
	import alternativa.engine3d.resources.Geometry;
	import alternativa.engine3d.resources.TextureResource;
	
	import avmplus.getQualifiedClassName;
	
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
	 * Mapped glow material. Apply this material to an object and then use <code>PostEffectRenderer</code> with <code>MappedGlow</code> effect to output final glow.
	 * 
	 * @author Varnius
	 */
	public class MappedGlowMaterial extends Material
	{		
		// Program cache for this material
		
		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;		
		private var programsCache:Dictionary;	
		
		// Maps
		
		/**
		 * Diffuse map.
		 */
		public var diffuseMap:TextureResource;
		
		/**
		 * Glow map.
		 */
		public var glowMap:TextureResource;
		
		// Internal properties
		
		/**
		 * @private
		 */
		alternativa3d static var glowRenderPass:Boolean = false;		
		
		/**
		 * Returns a new instance of this material.
		 * 
		 * @param diffuseMap Diffuse map.
		 * @param glowMap Map that marks areas that should glow.
		 */
		public function MappedGlowMaterial(diffuseMap:TextureResource, glowMap:TextureResource)
		{
			super();
			
			this.diffuseMap = diffuseMap;			
			this.glowMap = glowMap;
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
			if(diffuseMap == null || diffuseMap._texture == null || glowMap == null || glowMap._texture == null)
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
			
			var program:GlowMaterialProgram;
			
			program = getProgram(object, optionsPrograms, camera);
			
			// Prerender
			if(glowRenderPass)
			{
				createDrawUnitPrerender(program, camera, surface, geometry, objectRenderPriority);
			}
			// Final render
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
			
			if(diffuseMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(diffuseMap)) as Class, resourceType))
			{
				resources[diffuseMap] = true;
			}
			
			if(glowMap != null && A3DUtils.checkParent(getDefinitionByName(getQualifiedClassName(glowMap)) as Class, resourceType))
			{
				resources[glowMap] = true;
			}
		}
		
		/**
		 * Create material program.
		 */
		private function getProgram(object:Object3D, 
									programs:Dictionary,
									camera:Camera3D
		):GlowMaterialProgram
		{
			var key:String = glowRenderPass ? "glowPass1" : "glowPass2";
			var program:GlowMaterialProgram = programs[key];
			
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
				if(glowRenderPass)
				{
					// Vertex
					vertexLinker.addProcedure(vertexProcedure);
					vertexLinker.setInputParams(vertexProcedure, positionVar);
					
					// Fragment
					fragmentLinker.addProcedure(prerenderFragmentProcedure);
				}
				// Final render pass
				else
				{
					// Vertex	
					vertexLinker.addProcedure(vertexProcedure);
					vertexLinker.setInputParams(vertexProcedure, positionVar);
					
					// Fragment
					fragmentLinker.addProcedure(fragmentProcedure);
				}			
				
				fragmentLinker.varyings = vertexLinker.varyings;
				program = new GlowMaterialProgram(vertexLinker, fragmentLinker);	
					
				program.upload(camera.context3D);
				programs[key] = program;
			}
			
			return program;
		}
		
		/**
		 * Gets drawUnit for final render.
		 */
		private function createDrawUnitFinal(program:GlowMaterialProgram,
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
			drawUnit.setVertexBufferAt(program.aUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set constants
			object.setTransformConstants(drawUnit, surface, program.vertexShader, camera);
			drawUnit.setProjectionConstants(camera, program.cWorldViewProjMatrix, object.localToCameraTransform);
			
			// Set samplers
			drawUnit.setTextureAt(program.sDiffuseMap, diffuseMap._texture);
			
			drawUnit.blendSource = Context3DBlendFactor.SOURCE_ALPHA;
			drawUnit.blendDestination = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;			
			camera.renderer.addDrawUnit(drawUnit, objectRenderPriority >= 0 ? objectRenderPriority : Renderer.OPAQUE);
		}
		
		/**
		 * Gets drawUnit for prerender.
		 */
		private function createDrawUnitPrerender(program:GlowMaterialProgram,
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
			var renderer:MappedGlowRenderer = camera.renderer as MappedGlowRenderer;
			
			// Create draw unit
			var drawUnit:DrawUnit = renderer.createGlowDrawUnit(object, program.program, geometry._indexBuffer, surface.indexBegin, surface.numTriangles, program);
			
			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, geometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(program.aUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set constants
			object.setTransformConstants(drawUnit, surface, program.vertexShader, camera);
			drawUnit.setProjectionConstants(camera, program.cWorldViewProjMatrix, object.localToCameraTransform);
			
			// Set samplers
			drawUnit.setTextureAt(program.sGlowMap, glowMap._texture);
			drawUnit.setTextureAt(program.sDiffuseMap, diffuseMap._texture);
			
			drawUnit.blendSource = Context3DBlendFactor.ONE;
			drawUnit.blendDestination = Context3DBlendFactor.ZERO;			
			camera.renderer.addDrawUnit(drawUnit, objectRenderPriority >= 0 ? objectRenderPriority : Renderer.OPAQUE);
		}
		
		/*---------------------------
		Vertex procedures
		---------------------------*/
		
		static alternativa3d const vertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#c0=cWorldViewProjMatrix",
			"#v0=vPosition",
			"#v1=vUV",
			
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
			// Declarations
			"#s0=sGlowMap",
			"#s1=sDiffuseMap",
			"#v0=vPosition",			
			"#v1=vUV",
			
			// Sample diffuse map
			"tex t0,v1,s1 <2d,repeat,linear>",
			// Sample glow map
			"tex t1,v1,s0 <2d,repeat,linear>",
			// Multiply diffuse map by glow map to get: result = diffuse.rgba * glow.x
			"mul o0 t0.xyzw t1.xxxx"
		], "fragmentProcedure");
		
		static alternativa3d const fragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",
			"#v0=vPosition",			
			"#v1=vUV",
			
			"tex t0,v1,s0 <2d,repeat,linear>",
			"mov o0 t0",
		], "fragmentProcedure");
	}
}

import alternativa.engine3d.materials.ShaderProgram;
import alternativa.engine3d.materials.compiler.Linker;

import flash.display3D.Context3D;

class GlowMaterialProgram extends ShaderProgram
{	
	// Vertex
	public var aPosition:int = -1;
	public var aUV:int = -1;
	public var cWorldViewProjMatrix:int = -1;
	
	// Fragment
	public var sDiffuseMap:int = -1;	
	
	// Fragment - prerender
	public var sGlowMap:int = -1;
	
	public function GlowMaterialProgram(vertex:Linker, fragment:Linker)
	{
		super(vertex, fragment);
	}
	
	override public function upload(context3D:Context3D):void
	{
		super.upload(context3D);
		
		// Vertex shader
		aPosition = vertexShader.findVariable("aPosition");
		aUV = vertexShader.findVariable("aUV");
		cWorldViewProjMatrix = vertexShader.findVariable("cWorldViewProjMatrix");	
		
		// Fragment shader
		sDiffuseMap = fragmentShader.findVariable("sDiffuseMap");
		
		// Fragment shader - prerender
		sGlowMap = fragmentShader.findVariable("sGlowMap");
	}
}