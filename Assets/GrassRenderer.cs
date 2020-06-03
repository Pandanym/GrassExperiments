using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class GrassRenderer : MonoBehaviour
{
    public Material grassMaterial;

    public int grassDensity;
    public int grassPatchSize;

    private List<GrassBlade> grassBlade = new List<GrassBlade>();
    private ComputeBuffer grassBladeBuffer;
    private CommandBuffer grassCommandBuffer;

    private int InstanceCount { get => (grassPatchSize* grassDensity) * (grassPatchSize * grassDensity); }

    // Start is called before the first frame update
    void Start()
    {
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

            grassBlade.Add(new GrassBlade(position));
        }

        grassBladeBuffer = new ComputeBuffer(InstanceCount, sizeof(float) * 3); 
        Graphics.SetRandomWriteTarget(1, grassBladeBuffer);
        grassBladeBuffer.SetData(grassBlade);

        Shader.SetGlobalBuffer("GrassBladeBuffer", grassBladeBuffer);

        grassCommandBuffer = new CommandBuffer();
        grassCommandBuffer.DrawProcedural(this.transform.localToWorldMatrix, grassMaterial, -1, MeshTopology.Triangles, 6 * InstanceCount, InstanceCount);
        Camera.main.AddCommandBuffer(UnityEngine.Rendering.CameraEvent.AfterForwardOpaque, grassCommandBuffer);

        grassBlade.Clear();
    }

    private void OnDestroy()
    {
        grassBladeBuffer.Release();
        Camera.main.RemoveCommandBuffer(CameraEvent.AfterForwardOpaque, grassCommandBuffer);
    }
}

public struct GrassBlade
{
    public Vector3 position;

    public GrassBlade(Vector3 position)
    {
        this.position = position;
    }
}