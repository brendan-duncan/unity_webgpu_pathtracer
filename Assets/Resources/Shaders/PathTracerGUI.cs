using System;
using UnityEngine;

#if UNITY_EDITOR
using UnityEditor;

public class PathTracerGUI : ShaderGUI
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        base.OnGUI(materialEditor, properties);
        Material targetMat = materialEditor.target as Material;
    }
}
#endif // UNITY_EDITOR
