import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialService {
  // Singleton pattern
  static final SerialService _instance = SerialService._internal();
  factory SerialService() => _instance;
  SerialService._internal();

  SerialPort? _port;
  final StreamController<List<int>> _dataStreamController = StreamController<List<int>>.broadcast();
  
  Stream<List<int>> get dataStream => _dataStreamController.stream;
  
  bool get isConnected => _port != null && _port!.isOpen;
  
  String? get connectedPort => _port?.name;


  List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  Future<void> connect(String portName) async {
    if (_port != null) {
      await disconnect();
    }

    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        throw Exception("Could not open serial port $portName");
      }

      final config = SerialPortConfig();
      config.baudRate = 115200;
      port.config = config;

      _port = port;
      
      final reader = SerialPortReader(_port!);
      reader.stream.listen((data) {
        _processData(data);
      });
    } catch (e) {
      print("Error connecting to port: $e");
      await disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_port != null) {
      if (_port!.isOpen) {
        _port!.close();
      }
      _port = null;
    }
  }

  String _buffer = "";

  void _processData(Uint8List data) {
    try {
      // Convert bytes to string and append to buffer
      String incoming = String.fromCharCodes(data);
      _buffer += incoming;

      // Split by newline
      while (_buffer.contains('\n')) {
        int index = _buffer.indexOf('\n');
        String line = _buffer.substring(0, index).trim();
        _buffer = _buffer.substring(index + 1);

        if (line.isNotEmpty) {
          _parseLine(line);
        }
      }
    } catch (e) {
      print("Error processing data: $e");
    }
  }

  void _parseLine(String line) {
    try {
      // CSV format: val1,val2,...,val64
      List<String> parts = line.split(',');
      if (parts.length == 64) {
        List<int> sensors = parts.map((e) {
           return int.tryParse(e) ?? 0;
        }).toList();
        
        _dataStreamController.add(sensors);
      }
    } catch (e) {
      print("Error parsing line: $e");
    }
  }

  void dispose() {
    disconnect();
    _dataStreamController.close();
  }
}
