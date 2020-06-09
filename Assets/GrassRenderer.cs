using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

public class GrassRenderer : MonoBehaviour
{
    public Material grassMaterial;

    public int grassDensity;
    public int grassPatchSize;
    public float grassHeight;

    public float springForce;
    public float springDamping;

    public float bendForce;

    private List<GrassBlade> grassBlade = new List<GrassBlade>();
    private ComputeBuffer grassBladeBuffer;
    private CommandBuffer grassCameraCommandBuffer;
    private CommandBuffer grassDepthCommandBuffer;
    private CommandBuffer grassLightCommandBuffer;
    private CommandBuffer setShadowTextureCommandBuffer;

    private int InstanceCount { get => (grassPatchSize* grassDensity) * (grassPatchSize * grassDensity); }

    private Camera cam;

    // Start is called before the first frame update
    void Start()
    {

        cam = Camera.main;

        Debug.Log($"Number of grass blades : {InstanceCount}");

        grassBlade = new List<GrassBlade>(InstanceCount);
        for (int i = 0; i < InstanceCount; i++)
        {
            Vector3 position = new Vector3(
                (float)(i % (grassPatchSize * grassDensity)) / grassDensity, // x
                0, // y
                (float)(i / (grassPatchSize * grassDensity)) / grassDensity // z
                );

            position += new Vector3(Random.Range(-.1f, .1f), 0, Random.Range(-.1f, .1f)); // add random offset

            grassBlade.Add(new GrassBlade(position, grassHeight + Random.Range(-.2f, .2f), 0, Vector3.right));
        }

        grassBladeBuffer = new ComputeBuffer(InstanceCount, Marshal.SizeOf(typeof(GrassBlade))); 
        Graphics.SetRandomWriteTarget(1, grassBladeBuffer);
        grassBladeBuffer.SetData(grassBlade);

        Shader.SetGlobalBuffer("GrassBladeBuffer", grassBladeBuffer);

        grassCameraCommandBuffer = new CommandBuffer();
        grassCameraCommandBuffer.SetGlobalInt("_Simulate", 0);
        grassCameraCommandBuffer.SetGlobalInt("_ShadowCaster", 0);
        grassCameraCommandBuffer.DrawProcedural(Matrix4x4.identity, grassMaterial, 0, MeshTopology.Triangles, 6 * InstanceCount, 1);
        grassCameraCommandBuffer.name = "Grass Geometry Buffer";
        cam.AddCommandBuffer(CameraEvent.BeforeForwardOpaque, grassCameraCommandBuffer);

        grassDepthCommandBuffer = new CommandBuffer();
        grassDepthCommandBuffer.SetGlobalInt("_Simulate", 1);
        grassCameraCommandBuffer.SetGlobalInt("_ShadowCaster", 0);
        grassDepthCommandBuffer.DrawProcedural(Matrix4x4.identity, grassMaterial, 0, MeshTopology.Triangles, 6 * InstanceCount, 1);
        grassDepthCommandBuffer.name = "Grass Depth Buffer";
        cam.AddCommandBuffer(CameraEvent.BeforeDepthTexture, grassDepthCommandBuffer);

        grassLightCommandBuffer = new CommandBuffer();
        grassLightCommandBuffer.SetGlobalInt("_Simulate", 0);
        grassCameraCommandBuffer.SetGlobalInt("_ShadowCaster", 1);
        grassLightCommandBuffer.DrawProcedural(Matrix4x4.identity, grassMaterial, 0, MeshTopology.Triangles, 6 * InstanceCount, 1);
        grassLightCommandBuffer.name = "Grass Shadows Caster Buffer";
        FindObjectOfType<Light>().AddCommandBuffer(LightEvent.BeforeShadowMapPass, grassLightCommandBuffer);

        setShadowTextureCommandBuffer = new CommandBuffer();
        setShadowTextureCommandBuffer.name = "Get Shadow Texture Buffer";
        setShadowTextureCommandBuffer.SetGlobalTexture("_ShadowTexture", BuiltinRenderTextureType.CurrentActive);
        FindObjectOfType<Light>().AddCommandBuffer(LightEvent.AfterScreenspaceMask, setShadowTextureCommandBuffer);

        grassBlade.Clear();
    }

    Vector3 previousHitPoint;
    private void Update()
    {
        Plane plane = new Plane(Vector3.up, transform.position);
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);

        float distance;
        if (plane.Raycast(ray, out distance))
        {
            Vector3 hitPoint = ray.GetPoint(distance);

            if ((hitPoint - previousHitPoint).magnitude > 0) Shader.SetGlobalVector("_PointerDirection", (hitPoint - previousHitPoint));
            else Shader.SetGlobalVector("_PointerDirection", Vector3.up);

            previousHitPoint = hitPoint;

            Shader.SetGlobalVector("_PointerPos", hitPoint);
        }


        Shader.SetGlobalInt("_PointerActive", Input.GetMouseButton(0) ? 1 : 0);

        Shader.SetGlobalFloat("_GrassSpringForce", springForce);
        Shader.SetGlobalFloat("_GrassSpringDamping", springDamping);
        Shader.SetGlobalFloat("_GrassBendForce", bendForce);
    }

    private void OnDestroy()
    {
        grassBladeBuffer.Release();
        grassBladeBuffer.Dispose();
        grassBladeBuffer = null;

        if (!cam) return;

        FindObjectOfType<Light>().RemoveAllCommandBuffers();

        cam.RemoveAllCommandBuffers();
    }
}

public struct GrassBlade
{
    public Vector3 position;
    public float height;
    public float defaultHeight;
    public float bend; 
    public float bendVelocity;
    public Vector3 direction;

    public GrassBlade(Vector3 position, float height, float bend, Vector3 direction)
    {
        this.position = position;
        this.height = height;
        this.defaultHeight = height;
        this.bend = bend;
        this.direction = direction;
        this.bendVelocity = 0;
    }

}