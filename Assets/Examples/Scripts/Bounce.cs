using UnityEngine;

public class Bounce : MonoBehaviour
{
    Vector3 startPosition;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        startPosition = transform.position;
    }

    // Update is called once per frame
    void Update()
    {
        transform.position = startPosition + new Vector3(0, startPosition.y + Mathf.Sin(Time.time * 2)*2, 0);
    }
}
