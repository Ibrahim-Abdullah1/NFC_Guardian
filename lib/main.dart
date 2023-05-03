import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:camera/camera.dart';
import 'package:location/location.dart' as loc;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  MyApp({required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: NFCDetector(cameras: cameras),
    );
  }
}

class NFCDetector extends StatefulWidget {
  final List<CameraDescription> cameras;

  NFCDetector({required this.cameras});

  @override
  _NFCDetectorState createState() => _NFCDetectorState();
}

class _NFCDetectorState extends State<NFCDetector> {
  late CameraController _cameraController;
  late loc.Location _location;
  String _emailAddress = 'example@example.com';

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );
    _location = loc.Location();
    _initializeCamera();
    _initializeNFC();
  }

  String _extractTagId(NfcTag tag) {
    if (Platform.isAndroid) {
      if (tag.data.containsKey('android.nfc.tech.NfcA')) {
        return tag.data['android.nfc.tech.NfcA']['id'] ?? 'unknown';
      } else if (tag.data.containsKey('android.nfc.tech.NfcB')) {
        return tag.data['android.nfc.tech.NfcB']['id'] ?? 'unknown';
      } else if (tag.data.containsKey('android.nfc.tech.NfcF')) {
        return tag.data['android.nfc.tech.NfcF']['id'] ?? 'unknown';
      } else if (tag.data.containsKey('android.nfc.tech.NfcV')) {
        return tag.data['android.nfc.tech.NfcV']['id'] ?? 'unknown';
      } else if (tag.data.containsKey('android.nfc.tech.NfcBarcode')) {
        return tag.data['android.nfc.tech.NfcBarcode']['id'] ?? 'unknown';
      }
    } else if (Platform.isIOS) {
      return tag.data['iso7816']?['identifier'] ?? 'unknown';
    }
    return 'unknown';
  }

  Future<void> _initializeCamera() async {
    await _cameraController.initialize();
  }

  Future<void> _initializeNFC() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      print("NFC is not available");
      return;
    }

    _startNFCDetection();
  }

  Future<void> _startNFCDetection() async {
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        String tagId = _extractTagId(tag);
        print('NFC tag detected: $tagId');

        NfcManager.instance.stopSession();
        await _sendEmailWithLocationAndPictures();
        _startNFCDetection();
      },
    );
  }

  Future<void> _sendEmailWithLocationAndPictures() async {
    // Take pictures from both cameras
    List<File> images = [];
    for (CameraDescription camera in widget.cameras) {
      _cameraController = CameraController(camera, ResolutionPreset.medium);
      await _cameraController.initialize();
      XFile image = await _cameraController.takePicture();
      images.add(File(image.path));
    }

    // Get the current location
    loc.LocationData location = await _location.getLocation();

    // Send the email
    await _sendEmail(location, images);
  }

  Future<void> _sendEmail(loc.LocationData location, List<File> images) async {
    // Set up the SMTP server (use the SMTP server of your choice)
    final smtpServer = gmail('your_email@gmail.com', 'your_password');

    // Construct the email
    final message = Message()
      ..from = Address('your_email@gmail.com', 'Your Name')
      ..recipients.add(Address(_emailAddress))
      ..subject = 'NFC Chip Disconnected: ${DateTime.now()}'
      ..text =
          'The NFC chip has been disconnected. Here is the location and pictures from both cameras:'
      ..html = "<h3>Location:</h3>\n"
          "<p>Latitude: ${location.latitude}<br>"
          "Longitude: ${location.longitude}</p>"
          "<h3>Pictures:</h3>";
    for (int i = 0; i < images.length; i++) {
      message.attachments.add(FileAttachment(images[i])
        ..fileName = 'image${i + 1}.jpg'
        ..contentType = 'image/jpeg');
      message.html ??= '';
      message.html ??= '';
      message.html = message.html! +
          '<img src="cid:image${i + 1}.jpg" alt="Camera Image ${i + 1}"><br>';
    }

    try {
      final sendReport = await send(message, smtpServer);
      print('Message sent: ' + sendReport.toString());
    } on MailerException catch (e) {
      print('Message not sent. \nError: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('NFC Chip Detector')),
      body: Center(
        child: Text(
          'Place the phone near the NFC chip.\n'
          'The app will send an email with location and pictures once the phone is disconnected from the NFC chip.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
