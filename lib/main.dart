import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef; // Add this import
import 'package:camera/camera.dart';
import 'package:location/location.dart' as loc;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter_background/flutter_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

// Rest of the code (unchanged until _NFCDetectorState class)

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
  String _nfcStatus = 'Trying to connect with NFC...';
  String _nfcErrorMessage = '';

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

  Future<void> _initializeCamera() async {
    await _cameraController.initialize();
  }

  Future<void> _initializeNFC() async {
    // Configure the background execution (Android only)
    if (Platform.isAndroid) {
      final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'NFC Chip Detector',
        notificationText: 'Running in the background...',
        notificationImportance: AndroidNotificationImportance.Default,
        notificationIcon: AndroidResource(
            name: 'background_icon', defType: 'drawable'), // Add this line
      );
      await FlutterBackground.initialize(androidConfig: androidConfig);
    }

    // Check if the app has permissions
    bool hasPermissions = await FlutterBackground.hasPermissions;
    if (!hasPermissions) {
      await FlutterBackground.initialize();
    }

    NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
    if (availability == NFCAvailability.available) {
      _startNFCDetection();
    } else {
      _nfcStatus = 'NFC not available';
      _startNFCDetection();
    }
  }

  Future<void> _startNFCDetection() async {
    setState(() {
      _nfcStatus = 'Trying to connect with NFC...';
    });

    // Request permission for background location (required for Android)
    if (Platform.isAndroid) {
      await FlutterBackground.enableBackgroundExecution();
      await _location.requestPermission();
    }

    bool tagConnected = false;

    try {
      while (true) {
        NFCTag nfcTag = await FlutterNfcKit.poll();

        // Check if the tag supports any of the desired types
        if (nfcTag.type != NFCTagType.unknown) {
          setState(() {
            _nfcStatus = 'Connecting to NFC Chip...';
          });

          if (nfcTag.id.isNotEmpty) {
            tagConnected = true;
            setState(() {
              _nfcStatus = 'Connection Successful';
            });
          } else {
            setState(() {
              _nfcStatus = 'Not supported NFC chip';
            });
          }
        } else {
          setState(() {
            _nfcStatus = 'Not supported NFC chip';
          });
        }

        // If the tag was connected but is now disconnected
        if (tagConnected && nfcTag.type == NFCTagType.unknown) {
          tagConnected = false;
          await _sendEmailWithLocationAndPictures();
        }
      }
    } on PlatformException catch (e) {
      setState(() {
        _nfcErrorMessage = "Platform exception: ${e.message}";
      });
    } catch (e) {
      setState(() {
        _nfcErrorMessage = "Unknown exception: $e";
      });
    }
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
      message.html =
          '${message.html!}<img src="cid:image${i + 1}.jpg" alt="Camera Image ${i + 1}"><br>';
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _nfcStatus,
              style: const TextStyle(fontSize: 24, color: Colors.blueGrey),
            ),
            const SizedBox(height: 20),
            const Text(
              'Place the phone near the NFC chip.\n'
              'The app will send an email with location and pictures once the phone is disconnected from the NFC chip.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            if (_nfcErrorMessage.isNotEmpty)
              Text(
                _nfcErrorMessage,
                style: TextStyle(fontSize: 18, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
