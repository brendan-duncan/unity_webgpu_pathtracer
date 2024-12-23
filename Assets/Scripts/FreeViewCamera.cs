using UnityEngine;

[RequireComponent(typeof(Camera))]
public class FreeViewCamera : MonoBehaviour
{
    public float movementSpeed = 10.0f;
    public float rotationSpeed = 2.0f;
    public float momentumFactor = 0.1f;

    private Vector3 currentVelocity;
    private Vector3 targetVelocity;
    private Raytracer rayTracer;

    private void Start()
    {
        rayTracer = GetComponent<Raytracer>();
    }

    private void Update()
    {
        // Camera rotation when the right mouse button is held down
        if (Input.GetMouseButton(1))
        {
            float mouseX = Input.GetAxis("Mouse X") * rotationSpeed;
            float mouseY = Input.GetAxis("Mouse Y") * rotationSpeed;

            transform.Rotate(-mouseY, mouseX, 0);
            transform.eulerAngles = new Vector3(transform.eulerAngles.x, transform.eulerAngles.y, 0);
            if (rayTracer != null)
            {
                rayTracer.ResetSamples();
            }
        }

        // Camera movement
        Vector3 movementDirection = Vector3.zero;
        if (Input.GetKey(KeyCode.W)) movementDirection += transform.forward;
        if (Input.GetKey(KeyCode.S)) movementDirection -= transform.forward;
        if (Input.GetKey(KeyCode.A)) movementDirection -= transform.right;
        if (Input.GetKey(KeyCode.D)) movementDirection += transform.right;

        float speedModifier = 1.0f;
        if (Input.GetKey(KeyCode.LeftShift))
        {
            speedModifier = 10.0f;
        }

        targetVelocity = movementDirection.normalized * (movementSpeed * speedModifier);
        currentVelocity = Vector3.Lerp(currentVelocity, targetVelocity, momentumFactor);

        if (currentVelocity != Vector3.zero)
        {
            if (rayTracer != null)
            {
                rayTracer.ResetSamples();
            }
            transform.position += currentVelocity * Time.deltaTime;
        }
    }
}
