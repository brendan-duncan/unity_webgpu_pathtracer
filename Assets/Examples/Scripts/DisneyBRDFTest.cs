using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class DisneyBRDFTest : MonoBehaviour
{
    public PathTracer pathTracer;
    public Slider anisotropicSlider;
    public Slider sheenSlider;
    public Slider sheenTintSlider;
    public Slider specularSlider;
    public Slider specularTintSlider;
    public Slider subsurfaceSlider;
    public Slider clearCoatSlider;
    public Slider clearCoatGlossSlider;
    public Slider metallicSlider;
    public Slider roughnessSlider;
    public Slider opacitySlider;
    public Slider iorSlider;
    public MeshRenderer mesh;

    List<Renderer> objects = new List<Renderer>();

    void Start()
    {
        /*Random.InitState(42);
        for (int z = 0; z < 10; ++z)
        {
            for (int x = 0; x < 10; ++x)
            {
                GameObject sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                sphere.transform.position = new Vector3(x - 5.0f, 0.5f, z - 5.0f);
                Material material = new Material(Shader.Find("PathTracer/DisneyBRDF"));
                Renderer renderer = sphere.GetComponent<Renderer>();
                renderer.material = material;
                objects.Add(renderer);

                float u = x / 9.0f;
                float v = z / 9.0f;

                material.SetColor("baseColorFactor", new Color(Random.Range(0.2f, 0.95f), Random.Range(0.2f, 0.95f), Random.Range(0.2f, 0.95f)));
                material.SetFloat("metallicFactor", 1.0f - u);
                material.SetFloat("roughnessFactor", 1.0f - v);
            }
        }*/
        objects.Add(mesh);
    }

    void Update()
    {
        bool changed = false;
        foreach (Renderer renderer in objects)
        {
            Material material = renderer.sharedMaterial;
            Color baseColor = material.GetColor("baseColorFactor");
            if (material.GetFloat("anisotropicFactor") != anisotropicSlider.value ||
                material.GetFloat("sheenFactor") != sheenSlider.value ||
                material.GetFloat("sheenTint") != sheenTintSlider.value ||
                material.GetFloat("specularFactor") != specularSlider.value ||
                material.GetFloat("specularTint") != specularTintSlider.value ||
                material.GetFloat("subsurfaceFactor") != subsurfaceSlider.value ||
                material.GetFloat("clearCoatFactor") != clearCoatSlider.value ||
                material.GetFloat("clearCoatGloss") != clearCoatGlossSlider.value ||
                material.GetFloat("metallicFactor") != metallicSlider.value ||
                material.GetFloat("roughnessFactor") != roughnessSlider.value ||
                material.GetFloat("ior") != iorSlider.value ||
                baseColor.a != opacitySlider.value)
            {
                changed = true;
            }
            baseColor.a = opacitySlider.value;
            material.SetColor("baseColorFactor", baseColor);
            material.SetFloat("anisotropicFactor", anisotropicSlider.value);
            material.SetFloat("sheenFactor", sheenSlider.value);
            material.SetFloat("sheenTint", sheenTintSlider.value);
            material.SetFloat("specularFactor", specularSlider.value);
            material.SetFloat("specularTint", specularTintSlider.value);
            material.SetFloat("subsurfaceFactor", subsurfaceSlider.value);
            material.SetFloat("clearCoatFactor", clearCoatSlider.value);
            material.SetFloat("clearCoatGloss", clearCoatGlossSlider.value);
            material.SetFloat("metallicFactor", metallicSlider.value);
            material.SetFloat("roughnessFactor", roughnessSlider.value);
            material.SetFloat("ior", iorSlider.value);
        }

        if (changed)
        {
            pathTracer.UpdateMaterialData();
        }
    }
}
