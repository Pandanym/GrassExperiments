using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class GrassRenderer : MonoBehaviour
{
    public Material grassMaterial;

    public int grassDensity;
    public int grassPatchSize;
    public float grassHeight;

    private List<GrassBlade> grassBlade = new List<GrassBlade>();
    private ComputeBuffer grassBladeBuffer;
    private CommandBuffer grassCommandBuffer;

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

            grassBlade.Add(new GrassBlade(position, grassHeight + Random.Range(-.2f, .2f)));
        }

        grassBladeBuffer = new ComputeBuffer(InstanceCount, sizeof(float) * 5); 
        Graphics.SetRandomWriteTarget(1, grassBladeBuffer);
        grassBladeBuffer.SetData(grassBlade);

        Shader.SetGlobalBuffer("GrassBladeBuffer", grassBladeBuffer);

        grassCommandBuffer = new CommandBuffer();
        grassCommandBuffer.DrawProcedural(this.transform.localToWorldMatrix, grassMaterial, -1, MeshTopology.Triangles, 6 * InstanceCount, 1);
        cam.AddCommandBuffer(UnityEngine.Rendering.CameraEvent.AfterForwardOpaque, grassCommandBuffer);

        grassBlade.Clear();
    }

    private void Update()
    {
        Plane plane = new Plane(Vector3.up, transform.position);
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);

        float distance;
        if (plane.Raycast(ray, out distance))
        {
            Vector3 hitPoint = ray.GetPoint(distance);

            Shader.SetGlobalVector("_PointerPos", hitPoint);
        }
    }

    private void OnDestroy()
    {
        grassBladeBuffer.Release();
        cam.RemoveCommandBuffer(CameraEvent.AfterForwardOpaque, grassCommandBuffer);
    }
}

public struct GrassBlade
{
    public Vector3 position;
    public float height;
    public float defaultHeight;

    public GrassBlade(Vector3 position, float height)
    {
        this.position = position;
        this.height = height;
        this.defaultHeight = height;
    }
}