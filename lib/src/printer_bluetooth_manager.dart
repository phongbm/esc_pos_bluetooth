/*
 * esc_pos_bluetooth
 * Created by Andrey Ushakov
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter_bluetooth_basic_updated/flutter_bluetooth_basic.dart';
import 'package:rxdart/rxdart.dart';

import './enums.dart';

/// Bluetooth printer
class PrinterBluetooth {
  PrinterBluetooth(this._device);

  final BluetoothDevice _device;

  String? get name => _device.name;

  String? get address => _device.address;

  int? get type => _device.type;

  bool? get connected => _device.connected;
}

/// Printer Bluetooth Manager
class PrinterBluetoothManager {
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;
  PrinterBluetooth? _connectedPrinter;
  bool _isPrinting = false;
  StreamSubscription? _scanResultsSubscription;
  StreamSubscription? _isScanningSubscription;

  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);

  Stream<bool> get isScanningStream => _isScanning.stream;

  final BehaviorSubject<List<PrinterBluetooth>> _scanResults =
      BehaviorSubject.seeded([]);

  Stream<List<PrinterBluetooth>> get scanResults => _scanResults.stream;

  Future _runDelayed(int seconds) {
    return Future<dynamic>.delayed(Duration(seconds: seconds));
  }

  void startScan(Duration timeout) async {
    _scanResults.add(<PrinterBluetooth>[]);

    _bluetoothManager.startScan(timeout: timeout);

    _scanResultsSubscription = _bluetoothManager.scanResults.listen((devices) {
      _scanResults.add(devices.map((d) => PrinterBluetooth(d)).toList());
    });

    _isScanningSubscription =
        _bluetoothManager.isScanning.listen((isScanningCurrent) async {
      // If isScanning value changed (scan just stopped)
      if (_isScanning.value && !isScanningCurrent) {
        _scanResultsSubscription!.cancel();
        _isScanningSubscription!.cancel();
      }
      _isScanning.add(isScanningCurrent);
    });
  }

  void stopScan() async {
    await _bluetoothManager.stopScan();
  }

  Future<PosPrintResult> writeBytes(
    List<int> bytes, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    final Completer<PosPrintResult> completer = Completer();

    if (_connectedPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotConnected);
    } else if (_isScanning.value) {
      return Future<PosPrintResult>.value(PosPrintResult.scanInProgress);
    } else if (_isPrinting) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }

    _writeBytes(bytes, chunkSizeBytes, queueSleepTimeMs, completer);

    // Printing timeout
    const int timeout = 5;
    _runDelayed(timeout).then((dynamic v) async {
      if (_isPrinting) {
        _isPrinting = false;
        completer.complete(PosPrintResult.timeout);
      }
    });

    return completer.future;
  }

  Future<PosPrintResult> printTicket(
    List<int> bytes, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    if (bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    return writeBytes(
      bytes,
      chunkSizeBytes: chunkSizeBytes,
      queueSleepTimeMs: queueSleepTimeMs,
    );
  }

  Future<bool> isConnected() async {
    return _connectedPrinter != null && await _bluetoothManager.isConnected;
  }

  Future<bool> connect(PrinterBluetooth printer) async {
    if (_connectedPrinter != null && await _bluetoothManager.isConnected) {
      if (printer.address == _connectedPrinter!.address) {
        return true;
      }
      await _bluetoothManager.disconnect();
    }

    await _bluetoothManager.connect(printer._device);
    _connectedPrinter = printer;
    return true;
  }

  Future<bool> disconnect() async {
    await _bluetoothManager.disconnect();
    _connectedPrinter = null;
    _isPrinting = false;
    return true;
  }

  void _writeBytes(
    List<int> bytes,
    int chunkSizeBytes,
    int queueSleepTimeMs,
    Completer<PosPrintResult> completer,
  ) async {
    _isPrinting = true;

    final len = bytes.length;
    List<List<int>> chunks = [];
    for (var i = 0; i < len; i += chunkSizeBytes) {
      var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
      chunks.add(bytes.sublist(i, end));
    }

    for (var i = 0; i < chunks.length; i += 1) {
      await _bluetoothManager.writeData(chunks[i]);
      sleep(Duration(milliseconds: queueSleepTimeMs));
    }

    _isPrinting = false;

    completer.complete(PosPrintResult.success);
  }
}
