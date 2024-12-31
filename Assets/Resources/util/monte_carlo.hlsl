#ifndef __UNITY_PATHRACER_MONTE_CARLO_HLSL__
#define __UNITY_PATHRACER_MONTE_CARLO_HLSL__

#include "brdf.hlsl"
#include "bvh.hlsl"
#include "common.hlsl"
#include "material.hlsl"
#include "sky.hlsl"
#include "disney.hlsl"

float3 TraceRayDisney(Ray ray, inout uint rngSeed)
{
    float3 radiance = 0.0f;
    float3 throughput = 1.0f;

    LightSampleRec lightSample = { (float3)0.0f, (float3)0.0f, (float3)0.0f, 0.0f, 0.0f };
    ScatterSampleRec scatterSample = { (float3)0.0f, (float3)0.0f, 0.0f };

    // For medium tracking
    bool inMedium = false;
    bool mediumSampled = false;
    bool surfaceScatter = false;

    const uint maxRayBounces = max(MaxRayBounces, 1u);
    
    for (uint rayDepth = 0; ; ++rayDepth)
    {
        RayHit hit = RayIntersect(ray);
        bool didHit = hit.distance < FarPlane;

        if (!didHit)
        {
            #if HAS_ENVIRONMENT_TEXTURE
            float4 envMapColPdf = EvalEnvMap(ray);
            float misWeight = 1.0;
            // Gather radiance from envmap and use scatterSample.pdf from previous bounce for MIS
            if (rayDepth > 0)
                misWeight = PowerHeuristic(scatterSample.pdf, envMapColPdf.w);

            if (misWeight > 0)
                radiance += misWeight * envMapColPdf.rgb * throughput * EnvironmentIntensity;
            #else
            #endif
            break;
        }

        DisneyMaterial material = GetDisneyMaterial(hit.material, hit.uv);

        // Gather radiance from emissive objects. Emission from meshes is not importance sampled
        radiance += material.emission * throughput;

        if (rayDepth == maxRayBounces)
            break;

        surfaceScatter = true;

        // Next event estimation
        //radiance += DirectLight(ray, hit, true) * throughput;

        // Sample BSDF for color and outgoing direction
        //scatterSample.f = DisneySample(hit, material, -ray.direction, hit.ffnormal, scatterSample.L, scatterSample.pdf, rngSeed);
        scatterSample.f = DisneySample(hit, material, -ray.direction, hit.normal, scatterSample.L, scatterSample.pdf, rngSeed);
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;
        else
            break;

        // Move ray origin to hit point and set direction for next bounce
        ray.direction = scatterSample.L;
        ray.origin = hit.position + ray.direction * 0.0001f;
    }

    return radiance;
}

float3 TraceRayMonteCarlo(Ray ray, inout uint rngSeed)
{
    float3 accumulatedColor = (float3)0.0f;
    float3 colorFactor = (float3)1.0f;

    for (uint rayDepth = 0; rayDepth < MaxRayBounces; ++rayDepth)
    {
        RayHit hit = RayIntersect(ray);
        bool didHit = hit.distance < FarPlane;
        if (didHit)
        {
            ray.direction = normalize(ray.direction);

            float4 albedoTransmission = GetAlbedoTransmission(hit.material, hit.uv);
            float2 metallicRoughness = GetMetallicRoughness(hit.material, hit.uv);
            float3 emission = GetEmission(hit.material, hit.uv);

            Material material = hit.material;
            float3 albedo = albedoTransmission.rgb;
            float transmission = albedoTransmission.a;
            float metallic = metallicRoughness.x;
            float roughness = metallicRoughness.y;
            float ior = material.ior;

            DisneyMaterial disneyMaterial = GetDisneyMaterial(material, hit.uv);
            hit.eta = dot(ray.direction, hit.normal) < 0.0 ? (1.0 / material.ior) : material.ior;

            float3 geometricNormal = GetGeometricNormal(hit);
            float3 shadingNormal = hit.normal;

            // Invert the normals if we're looking at the surface from the inside
            if (dot(geometricNormal, ray.direction) > 0.0f)
            {
                geometricNormal = -geometricNormal;
                shadingNormal = -shadingNormal;
                if (ior != 0.0f)
                {
                    ior = 1.0 / ior;
                }
            }

            /*if (EnvironmentMode == 1)
            {
                float2 u = float2(RandomFloat(rngSeed), RandomFloat(rngSeed));
                float3 sunDirection = SkyStateBuffer[0].sunDirection;
                float3 lightDirection = normalize(SampleSolarDiskDirection(u, SOLAR_COS_THETA_MAX, sunDirection));
                float3 lightIntensity = SampleSkyRadiance(ray.direction, 1);
                Ray shadowRay = { hit.position + lightDirection * 0.0001f, lightDirection };
                float lightVisibility = ShadowRay(shadowRay);
                float3 brdf = albedo * 0.31830987f;//FRAC_1_PI;
                float3 reflectance = brdf * dot(hit.normal, lightDirection);
                accumulatedColor += emission.rgb + lightIntensity * reflectance * lightIntensity * SOLAR_INV_PDF;
                return sunDirection;
            }
            else*/
            {
                accumulatedColor += emission.rgb * colorFactor;
            }

            //accumulatedColor += emission.rgb * colorFactor;

            /*if (material.textures.z >= 0.0f)
            {
                float3 tangent = normalize(hit.tangent);
                float3 normal = normalize(hit.normal);
                float3 bitangent = normalize(cross(shadingNormal, tangent));

                float3 normalSample = GetNormalMapSample(material, hit.uv);
                float3x3 normalBasis = float3x3(tangent, bitangent, normal);
                float3 newNormal = normalize(ToWorld(normalBasis, normalSample));
                shadingNormal = newNormal;
            }*/

            // MIS weights empirically chosen depending on what works better for which materials:
            //     roughness = 0, metallic = 0 : vndf + cosine + light
            //     roughness = 0, metallic = 1 : vndf
            //     roughness = 1, metallic = 0 : cosine + light
            //     roughness = 1, metallic = 1 : vndf
            //                transmission = 1 : vndf + transmission vndf

            float cosineSamplingWeight = (1.0f - metallic) * (1.0f - transmission);
            float lightSamplingWeight = 0.0f;//(1.0f - metallic) * (1.0f - transmission) * Select(0.0f, 1.0f, EmissiveTriangleCount > 0u);
            float vndfSamplingWeight = 1.0f - (1.0f - metallic) * roughness;
            float vndfTransmissionWeight = transmission;

            float sumSamplingWeights = cosineSamplingWeight + lightSamplingWeight + vndfSamplingWeight + vndfTransmissionWeight;

            cosineSamplingWeight /= sumSamplingWeights;
            lightSamplingWeight /= sumSamplingWeights;
            vndfSamplingWeight /= sumSamplingWeights;
            vndfTransmissionWeight /= sumSamplingWeights;

            float strategyPick = RandomFloat(rngSeed);

            Ray newRay = { hit.position, ray.direction };

            if (strategyPick < cosineSamplingWeight)
            {
                newRay.direction = RandomCosineHemisphere(shadingNormal, rngSeed);
            }
            else if (strategyPick < (cosineSamplingWeight + lightSamplingWeight))
            {
                newRay.direction = SampleVNDF(shadingNormal, -ray.direction, roughness, rngSeed);
            }
            else if (strategyPick < (cosineSamplingWeight + lightSamplingWeight + vndfSamplingWeight))
            {
                newRay.direction = SampleTransmissionVNDF(shadingNormal, -ray.direction, roughness, rngSeed);
            }
            else
            {
                //newRay.direction = RandomCosineHemisphere(shadingNormal, rngSeed);
                newRay.direction = SampleTransmissionVNDF(shadingNormal, -ray.direction, roughness, rngSeed);
                //newRay.direction = RandomCosineHemisphere(shadingNormal, rngSeed);
                /*float lightPick = (float)emissiveTriangles.count.x * RandomFloat(rngSeed);
                uint lightTriangleIndex = min(emissiveTriangles.count.x - 1, (uint)(floor(lightPick)));
                int lightTriangleAliasRecord = emissiveAliasTable[lightTriangleIndex];
                float lightSamplingProbability = bitcast<float>(lightTriangleAliasRecord.x);
                int lightTriangleAlias = lightTriangleAliasRecord.y;

                if (lightPick - (float)(lightTriangleIndex) > lightSamplingProbability)
                {
                    lightTriangleIndex = lightTriangleAlias;
                }

                int lightTriangle = emissiveTriangles.triangles[lightTriangleIndex].x;

                float2 lightUV = float2(RandomFloat(rngSeed), RandomFloat(rngSeed));
                if (dot(lightUV, (float2)1.0f) > 1.0f)
                {
                    lightUV = (float2)1.0f - lightUV;
                }

                float3 lightV0 = vertexPositions[3 * lightTriangle + 0u].xyz;
                float3 lightV1 = vertexPositions[3 * lightTriangle + 1u].xyz;
                float3 lightV2 = vertexPositions[3 * lightTriangle + 2u].xyz;

                float3 lightPoint = lightV0 * (1.0f - lightUV.x - lightUV.y) + lightV1 * lightUV.x + lightV2 * lightUV.y;

                newRay.direction = normalize(lightPoint - hit.point);*/
            }

            newRay.direction = normalize(newRay.direction);

            float cosineHemisphereProbability = max(0.0f, dot(newRay.direction, shadingNormal)) / PI;
            float vndfSamplingProbability = ProbabilityVNDF(shadingNormal, -ray.direction, newRay.direction, roughness);
            float vndfTransmissionProbability = ProbabilityTransmissionVNDF(shadingNormal, -ray.direction, newRay.direction, roughness);
            //float directLightSamplingProbability = LightSamplingProbability(newRay);

            // To properly apply MIS, one needs to compute the total probability of generating a reflected direction
            // using _all_possible_strategies_, see https://lisyarus.github.io/blog/posts/multiple-importance-sampling.html
            float totalMISProbability = cosineHemisphereProbability * cosineSamplingWeight
                + vndfSamplingProbability * vndfSamplingWeight
                + vndfTransmissionProbability * vndfTransmissionWeight
                /*+ directLightSamplingProbability * lightSamplingWeight*/;

            //totalMISProbability = 1.0 / (4.0 * PI);
            //newRay.direction = RandomSphere(rngSeed);

            float ndotr = dot(shadingNormal, newRay.direction);

            if (transmission > 0.0 || ndotr > 0.0)
            {
                float3 brdf = CookTorranceGGX(shadingNormal, newRay.direction, -ray.direction, albedo, metallic, roughness, ior, transmission);

                colorFactor *= brdf * abs(ndotr) / max(1e-8f, totalMISProbability);

                // Offset ray origin to side of the surface where new ray direction is pointing to,
                // to prevent self-intersection artifacts
                newRay.origin += sign(dot(newRay.direction, geometricNormal)) * geometricNormal * 0.0001f;
                //newRay.origin = hit.position + hit.normal * 0.001f;

                ray = newRay;
            }
            else
            {
                // Non-transmissive material and the new ray points inside the object
                // => brdf would return zero, colorFactor would be zero, and all
                // further recursive rays will be useless
                // Instead, just ignore this ray altogether
                break;
            }
        }
        else
        {
            accumulatedColor += colorFactor * SampleSkyRadiance(ray.direction, rayDepth);
            break;
        }
    }

    return accumulatedColor;
}

#endif // __UNITY_PATHRACER_MONTE_CARLO_HLSL__
