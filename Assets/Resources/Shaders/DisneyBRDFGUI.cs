using System;
using UnityEngine;
using UnityEditor;

#if UNITY_EDITOR
public class DisneyBRDFGUI : ShaderGUI
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        base.OnGUI(materialEditor, properties);
        Material targetMat = materialEditor.target as Material;
    }
}
#endif // UNITY_EDITOR
