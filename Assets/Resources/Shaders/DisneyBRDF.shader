Shader "PathTracer/DisneyBRDF"
{
    Properties
    {
        baseColorFactor("Base Color", Color) = (1, 1, 1, 1)
        baseColorTexture ("Base Color", 2D) = "white" {}

        normalTexture ("Normal", 2D) = "" {}
        normalScale ("Normal Scale", Range(0.0, 3.0)) = 1.0

        //_Opacity ("Opacity", Range(0.0, 1.0)) = 1.0
        //[Enum(Opaque,0, Blend,1, Mask,2)] _AlphaMode ("Alpha Mode", Range(0, 2)) = 0
        //alphaCutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        
        [HDR] emissiveFactor ("Emission", Color) = (0, 0, 0, 0)
        emissiveTexture ("Emission", 2D) = "white" {}

        anisotropicFactor ("Anisotropic", Range(0.0, 1.0)) = 0.0

        metallicFactor ("Metallic", Range(0.0, 1.0)) = 0
        roughnessFactor ("Roughness", Range(0.0, 1.0)) = 0.5
        metallicRoughnessTexture ("MetallicRoughness", 2D) = "" {}

        specularFactor ("Specular", Range(0.0, 2.0)) = 0.5
        specularTint ("Specular Tint", Range(0.0, 1.0)) = 0.0

        sheenFactor ("Sheen", Range(0.0, 1.0)) = 0.0
        sheenTint ("Sheen Tint", Range(0.0, 1.0)) = 0.5

        subsurfaceFactor ("Subsurface", Range(0.0, 1.0)) = 0

        clearCoatFactor ("Clear Coat", Range(0.0, 1.0)) = 0.0
        clearCoatGloss ("Clear Coat Gloss", Range(0.0, 1.0)) = 1.0

        ior ("IOR", Range(1.0, 3.0)) = 1.5
    }
    SubShader
    {
        Blend SrcAlpha OneMinusSrcAlpha
        Tags
        {
            "Queue" = "Transparent" "IgnoreProjector"="True" "RenderType"="Transparent"
        }

        CGINCLUDE
        
        #include "UnityPBSLighting.cginc"
        #include "AutoLight.cginc"

        #define PI 3.14159265f

        sampler2D baseColorTexture;
        sampler2D normalTexture;
        sampler2D emissiveTexture;
        sampler2D metallicRoughnessTexture;

        float4 baseColorFactor;
        float normalScale;
        float4 emissiveFactor;
        float anisotropicFactor;
        float metallicFactor;
        float roughnessFactor;
        float specularFactor;
        float specularTint;
        float sheenFactor;
        float sheenTint;
        float subsurfaceFactor;
        float clearCoatFactor;
        float clearCoatGloss;
        float ior;

        //sampler2D _AlbedoTex, _NormalTex, _TangentTex;
        //float3 _BaseColor;
        //float _NormalStrength, _Roughness, _Metallic, _Subsurface, _Specular, _SpecularTint, _Anisotropic, _Sheen, _SheenTint, _ClearCoat, _ClearCoatGloss;

        struct VertexData
        {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            float4 tangent : TANGENT;
            float2 uv : TEXCOORD0;
        };

        struct v2f
        {
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 normal : TEXCOORD1;
            float4 tangent : TEXCOORD2;
            float3 worldPos : TEXCOORD3;
            float3 objectPos : TEXCOORD4;
            SHADOW_COORDS(5)
        };

        float sqr(float x)
        {
            return x * x; 
        }

        float luminance(float3 color)
        {
            return dot(color, float3(0.299f, 0.587f, 0.114f));
        }

        float SchlickFresnel(float x)
        {
            x = saturate(1.0f - x);
            float x2 = x * x;
            return x2 * x2 * x; // While this is equivalent to pow(1 - x, 5) it is two less mult instructions
        }

        // Isotropic Generalized Trowbridge Reitz with gamma == 1
        float GTR1(float ndoth, float a)
        {
            float a2 = a * a;
            float t = 1.0f + (a2 - 1.0f) * ndoth * ndoth;
            return (a2 - 1.0f) / (PI * log(a2) * t);
        }

        // Anisotropic Generalized Trowbridge Reitz with gamma == 2. This is equal to the popular GGX distribution.
        float AnisotropicGTR2(float ndoth, float hdotx, float hdoty, float ax, float ay)
        {
            return rcp(PI * ax * ay * sqr(sqr(hdotx / ax) + sqr(hdoty / ay) + sqr(ndoth)));
        }

        // Isotropic Geometric Attenuation Function for GGX. This is technically different from what Disney uses, but it's basically the same.
        float SmithGGX(float alphaSquared, float ndotl, float ndotv)
        {
            float a = ndotv * sqrt(alphaSquared + ndotl * (ndotl - alphaSquared * ndotl));
            float b = ndotl * sqrt(alphaSquared + ndotv * (ndotv - alphaSquared * ndotv));
            return 0.5f / (a + b);
        }

        // Anisotropic Geometric Attenuation Function for GGX.
        float AnisotropicSmithGGX(float ndots, float sdotx, float sdoty, float ax, float ay)
        {
            return rcp(ndots + sqrt(sqr(sdotx * ax) + sqr(sdoty * ay) + sqr(ndots)));
        }

        struct BRDFResults
        {
            float3 diffuse;
            float3 specular;
            float3 clearcoat;
        };

        BRDFResults DisneyBRDF(float3 baseColor, float3 L, float3 V, float3 N, float3 X, float3 Y)
        {
            BRDFResults output;
            output.diffuse = 0.0f;
            output.specular = 0.0f;
            output.clearcoat = 0.0f;

            float3 H = normalize(L + V); // Microfacet normal of perfect reflection

            float ndotl = DotClamped(N, L);
            float ndotv = DotClamped(N, V);
            float ndoth = DotClamped(N, H);
            float ldoth = DotClamped(L, H);

            float3 surfaceColor = baseColor * baseColorFactor.rgb;

            float Cdlum = luminance(surfaceColor);

            float3 Ctint = Cdlum > 0.0f ? surfaceColor / Cdlum : 1.0f;
            float3 Cspec0 = lerp(specularFactor * 0.08f * lerp(1.0f, Ctint, specularTint), surfaceColor, metallicFactor);
            float3 Csheen = lerp(1.0f, Ctint, sheenTint);


            // Disney Diffuse
            float FL = SchlickFresnel(ndotl);
            float FV = SchlickFresnel(ndotv);

            float Fss90 = ldoth * ldoth * roughnessFactor;
            float Fd90 = 0.5f + 2.0f * Fss90;

            float Fd = lerp(1.0f, Fd90, FL) * lerp(1.0f, Fd90, FV);

            // Subsurface Diffuse (Hanrahan-Krueger brdf approximation)

            float Fss = lerp(1.0f, Fss90, FL) * lerp(1.0f, Fss90, FV);
            float ss = 1.25f * (Fss * (rcp(ndotl + ndotv) - 0.5f) + 0.5f);

            // Specular
            float alpha = roughnessFactor;
            float alphaSquared = alpha * alpha;

            // Anisotropic Microfacet Normal Distribution (Normalized Anisotropic GTR gamma == 2)
            float aspectRatio = sqrt(1.0f - anisotropicFactor * 0.9f);
            float alphaX = max(0.001f, alphaSquared / aspectRatio);
            float alphaY = max(0.001f, alphaSquared * aspectRatio);
            float Ds = AnisotropicGTR2(ndoth, dot(H, X), dot(H, Y), alphaX, alphaY);

            // Geometric Attenuation
            float GalphaSquared = sqr(0.5f + roughnessFactor * 0.5f);
            float GalphaX = max(0.001f, GalphaSquared / aspectRatio);
            float GalphaY = max(0.001f, GalphaSquared * aspectRatio);
            float G = AnisotropicSmithGGX(ndotl, dot(L, X), dot(L, Y), GalphaX, GalphaY);
            G *= AnisotropicSmithGGX(ndotv, dot(V, X), dot (V, Y), GalphaX, GalphaY); // specular brdf denominator (4 * ndotl * ndotv) is baked into output here (I assume at least)  

            // Fresnel Reflectance
            float FH = SchlickFresnel(ldoth);
            float3 F = lerp(Cspec0, 1.0f, FH);

            // Sheen
            float3 Fsheen = FH * sheenFactor * Csheen;

            // Clearcoat (Hard Coded Index Of Refraction -> 1.5f -> F0 -> 0.04)
            float Dr = GTR1(ndoth, lerp(0.1f, 0.001f, clearCoatGloss)); // Normalized Isotropic GTR Gamma == 1
            float Fr = lerp(0.04, 1.0f, FH);
            float Gr = SmithGGX(ndotl, ndotv, 0.25f);
            
            output.diffuse = (1.0f / PI) * (lerp(Fd, ss, subsurfaceFactor) * surfaceColor + Fsheen) * (1 - metallicFactor);
            output.specular = Ds * F * G;
            output.clearcoat = 0.25f * clearCoatFactor * Gr * Fr * Dr;

            return output;
        }

        ENDCG

        Pass
        {
            Tags
            {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM

            #pragma vertex vp
            #pragma fragment fp

            #pragma multi_compile _ SHADOWS_SCREEN

            v2f vp(VertexData v)
            {
                v2f i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.worldPos = mul(unity_ObjectToWorld, v.vertex);
                i.objectPos = v.vertex;
                i.normal = UnityObjectToWorldNormal(v.normal);
                i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                i.uv = v.uv;
                TRANSFER_SHADOW(i);

                return i;
            }

            float4 fp(v2f i) : SV_TARGET
            {
                float2 uv = i.uv;
                
                float3 unnormalizedNormalWS = i.normal;
                float renormFactor = 1.0f / length(unnormalizedNormalWS);

                float3x3 worldToTangent;
                float3 bitangent = cross(unnormalizedNormalWS, i.tangent.xyz) * i.tangent.w;
                worldToTangent[0] = i.tangent.xyz * renormFactor;
                worldToTangent[1] = bitangent * renormFactor;
                worldToTangent[2] = unnormalizedNormalWS * renormFactor;

                // Unpack DXT5nm tangent space normal
                float4 packedNormal = tex2D(normalTexture, uv);
                packedNormal.w *= packedNormal.x;

                float3 N;
                N.xy = packedNormal.wy * 2.0f - 1.0f;
                N.xy *= normalScale;
                N.z = sqrt(1.0f - saturate(dot(N.xy, N.xy)));
                N = mul(N, worldToTangent);

                // Unpack DXT5nm tangent space tangent
                //float3 T;
                //T.xy = tex2D(_TangentTex, uv).wy * 2 - 1;
                //T.z = sqrt(1 - saturate(dot(T.xy, T.xy)));
                //T = mul(lerp(float3(1.0f, 0.0f, 0.0f), T, saturate(normalScale)), worldToTangent);
                float3 T = i.tangent.xyz;
                
                float3 albedo = tex2D(baseColorTexture, uv).rgb;

                float3 L = normalize(_WorldSpaceLightPos0.xyz); // Direction *towards* light source
                float3 V = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz); // Direction *towards* camera
                float3 X = normalize(T);
                float3 Y = normalize(cross(N, T) * i.tangent.w);

                BRDFResults reflection = DisneyBRDF(albedo, L, V, N, X, Y);

                float3 output = _LightColor0 * (reflection.diffuse + reflection.specular + reflection.clearcoat);
                output *= DotClamped(N, L);
                output *= SHADOW_ATTENUATION(i);

                return float4(max(0.0f, output), baseColorFactor.a);
            }

            ENDCG
        }

        Pass
        {
            Tags
            {
                "LightMode" = "ForwardAdd"
            }

            Blend One One
            Zwrite Off

            CGPROGRAM

            #pragma vertex vp
            #pragma fragment fp

            #pragma multi_compile _ SHADOWS_SCREEN

            v2f vp(VertexData v)
            {
                v2f i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.worldPos = mul(unity_ObjectToWorld, v.vertex);
                i.objectPos = v.vertex;
                i.normal = UnityObjectToWorldNormal(v.normal);
                i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                i.uv = v.uv;
                TRANSFER_SHADOW(i);

                return i;
            }

            float4 fp(v2f i) : SV_TARGET
            {
                float2 uv = i.uv;
                
                float3 unnormalizedNormalWS = i.normal;
                float renormFactor = 1.0f / length(unnormalizedNormalWS);

                float3x3 worldToTangent;
                float3 bitangent = cross(unnormalizedNormalWS, i.tangent.xyz) * i.tangent.w;
                worldToTangent[0] = i.tangent.xyz * renormFactor;
                worldToTangent[1] = bitangent * renormFactor;
                worldToTangent[2] = unnormalizedNormalWS * renormFactor;

                // Unpack DXT5nm tangent space normal
                float4 packedNormal = tex2D(normalTexture, uv);
                packedNormal.w *= packedNormal.x;

                float3 N;
                N.xy = packedNormal.wy * 2.0f - 1.0f;
                N.xy *= normalScale;
                N.z = sqrt(1.0f - saturate(dot(N.xy, N.xy)));
                N = mul(N, worldToTangent);

                // Unpack DXT5nm tangent space tangent
                //float3 T;
                //T.xy = tex2D(_TangentTex, uv).wy * 2 - 1;
                //T.z = sqrt(1 - saturate(dot(T.xy, T.xy)));
                //T = mul(lerp(float3(1.0f, 0.0f, 0.0f), T, saturate(normalScale)), worldToTangent);
                float3 T = i.tangent.xyz;
                
                float3 albedo = tex2D(baseColorTexture, uv).rgb;

                float3 L = normalize(_WorldSpaceLightPos0.xyz); // Direction *towards* light source
                float3 V = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz); // Direction *towards* camera
                float3 X = normalize(T);
                float3 Y = normalize(cross(N, T) * i.tangent.w);

                BRDFResults reflection = DisneyBRDF(albedo, L, V, N, X, Y);

                float3 output = _LightColor0 * (reflection.diffuse + reflection.specular + reflection.clearcoat);
                output *= DotClamped(N, L);
                output *= SHADOW_ATTENUATION(i);

                return float4(max(0.0f, output), baseColorFactor.a);
            }

            ENDCG
        }

        Pass
        {
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            #include "UnityCG.cginc"

            struct ShadowVertexData
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct Shadowv2f
            {
                float4 pos : SV_POSITION;
            };

            Shadowv2f vp(ShadowVertexData v)
            {
                Shadowv2f o;

                o.pos = UnityClipSpaceShadowCasterPos(v.vertex.xyz, v.normal);
                o.pos = UnityApplyLinearShadowBias(o.pos);

                return o;
            }

            float4 fp(Shadowv2f i) : SV_Target
            {
                return 0;
            }

            ENDCG
        }
    }

    CustomEditor "DisneyBRDFGUI"
}
