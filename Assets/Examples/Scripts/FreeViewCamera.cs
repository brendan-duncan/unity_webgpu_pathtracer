using UnityEngine;

[RequireComponent(typeof(Camera))]
public class FreeViewCamera : MonoBehaviour
{
    public float movementSpeed = 10.0f;
    public float rotationSpeed = 2.0f;
    public float momentumFactor = 0.1f;

    Vector3 currentVelocity;
    Vector3 targetVelocity;

    float minVelocity = 1.0f;

    void Update()
    {
        // Camera rotation when the right mouse button is held down
        if (Input.GetMouseButton(1))
        {
            float mouseX = Input.GetAxis("Mouse X") * rotationSpeed;
            float mouseY = Input.GetAxis("Mouse Y") * rotationSpeed;

            transform.Rotate(-mouseY, mouseX, 0);
            transform.eulerAngles = new Vector3(transform.eulerAngles.x, transform.eulerAngles.y, 0);
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

        float currentSpeed = currentVelocity.magnitude;

        if (currentSpeed > minVelocity)
        {
            transform.position += currentVelocity * Time.deltaTime;
        }
    }
}
