import os
from azure.cognitiveservices.vision.face import FaceClient
from msrest.authentication import CognitiveServicesCredentials, BasicTokenAuthentication
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential 

FaceTokenCognitiveServicesEndpoint = "https://cognitiveservices.azure.com"
CognitiveFaceApiUrl= "https://xxx.cognitiveservices.azure.com/"
CognitiveFaceKey = ""

def get_face_client_with_key():
  # Create an authenticated FaceClient using API Key
  endpoint = CognitiveFaceApiUrl
  key = CognitiveFaceKey
  return FaceClient(endpoint, CognitiveServicesCredentials(key))

def get_face_client_with_mi():
  # Create an authenticated FaceClient.
  endpoint = CognitiveFaceApiUrl
  scope = FaceTokenCognitiveServicesEndpoint
  
  creds = ManagedIdentityCredential()
  access_token = creds.get_token(scope)
  #Convert to Dictionary
  dict_token = { "access_token": access_token.token}
  face_client = FaceClient(endpoint, BasicTokenAuthentication(dict_token))
  return face_client

def detect_face(face_client):
  # Detect a face in an image that contains a single face
  single_face_image_url = 'https://www.biography.com/.image/t_share/MTQ1MzAyNzYzOTgxNTE0NTEz/john-f-kennedy---mini-biography.jpg'
  single_image_name = os.path.basename(single_face_image_url)
  # We use detection model 3 to get better performance.
  detected_faces = face_client.face.detect_with_url(url=single_face_image_url, detection_model='detection_03')
  if not detected_faces:
      raise Exception('No face detected from image {}'.format(single_image_name))

  # Display the detected face ID in the first single-face image.
  # Face IDs are used for comparison to faces (their IDs) detected in other images.
  print('Detected face ID from', single_image_name, ':')
  for face in detected_faces: print (face.face_id)
  print()

#client = get_face_client_with_key()
client = get_face_client_with_mi()
detect_face(client)

