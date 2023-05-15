using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class DebugUI : MonoBehaviour
{
    [SerializeField] private Vector3 lightPosition;

    [SerializeField] private Light directionalLight;
    
    // Update is called once per frame
    void Update()
    {
        lightPosition = directionalLight.transform.position;
        //Debug.Log(lightPosition);
        Shader.SetGlobalVector("_VirtualLightPosition", lightPosition);
    }
}
