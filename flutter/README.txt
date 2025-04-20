The directories structure is as of a standard Flutter project.
The main code is located under the lib directory, and minor adaptation were made specifically for android and ios in the coresponding directories.

The primary file, `main.dart`, initializes the app by setting up Firebase and applying the app theme. It launches `InitialScreen`, which directs users to either the registration or chat screens based on authentication status.

The file `registration_screen.dart` handles user registration, allowing users to set up a nickname and optionally upload a profile image. It uses Firebase for authentication, Firestore to store user data, and Firebase Storage for image uploads.

The `contact_list.dart` file manages the user's contact list. It retrieves contacts from Firestore, provides search functionality, and tracks pending friend requests.

The `friend_request_handler.dart` file manages friend requests. It loads pending requests from Firestore, allows the user to accept or reject requests, and updates the contact list accordingly.

The `webrtc_chat_service.dart` file is the core of PriviChat's peer-to-peer communication system. It establishes and manages WebRTC-based connections between users. Key functionalities include setting up peer-to-peer connections using ICE servers, creating and managing data channels for messaging and file transfer, and buffering received files for handling large transfers. This file is critical to the app's main purpose

The `firebase_options.dart` file contains the necessary Firebase configuration options for initializing Firebase services in the app.