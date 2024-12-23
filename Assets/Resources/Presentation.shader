Shader "PathTracer/Presentation"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "white" {}
        Samples("Samples", Int) = 1
    }

    CGINCLUDE
        #include "UnityCG.cginc"
  
        struct Attributes
        {
            float4 vertex : POSITION;
            float4 texcoord : TEXCOORD0;
        };

        struct Varyings
        {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
        };

        sampler2D _MainTex;
        int Samples;

        Varyings VertBlit(Attributes v)
        {
            Varyings o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            return o;
        }

        half4 FragBlit(Varyings i) : SV_Target
        {
            //half4 col = half4(pow(tex2D(_MainTex, i.uv).rgb/* / (float)Samples*/, 1.0f/2.2f), 1.0f);
            half4 col = half4(tex2D(_MainTex, i.uv).rgb/* / (float)Samples*/, 1.0f);

            return col;
        }
    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM

                #pragma vertex VertBlit
                #pragma fragment FragBlit

            ENDCG
        }
    }
}