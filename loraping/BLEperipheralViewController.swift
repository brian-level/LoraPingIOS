//
//  BLEperipheralViewController.swift
//  bleboo
//
//  Created by Brian Dodge on 1/14/19.
//

import UIKit
import CoreBluetooth
import Foundation

class BLEperipheralViewController:  UIViewController,
                                    CBPeripheralDelegate
{
    //MARK: Properties
    @IBOutlet weak var devName: UILabel!
    @IBOutlet weak var findActivity: UIActivityIndicatorView!
    @IBOutlet weak var lightToggle: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var testResults: UILabel!
    @IBOutlet weak var byteRate: UILabel!
    
    var parentView : ViewController? = nil
    
    //MARK: Core Bluetooth members
    var centralMan : CBCentralManager?
    var thePeripheral : CBPeripheral?
    
    //MARK: services and characteristics database
    var services : [CBService] = [CBService]()
    var characters : [[CBCharacteristic]] = [[CBCharacteristic]()]
    
    //MARK: member vars
    var utils : BLEutils = BLEutils()
    var lastReadValue : String = ""
    
    var pollTimer : Timer = Timer()

    var cmdCharServiceIndex : Int = -1
    var cmdCharCharIndex : Int = 0
    
    var startTime : time_t = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
      
        // set this controller as peripheral's delegate
        thePeripheral?.delegate = self
    
        // Always adopt a light interface style.
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        } else {
            // Fallback on earlier versions
        }

        // set labels up
        if thePeripheral != nil && thePeripheral?.name != nil {
            devName.text = "Device: " + thePeripheral!.name!
        }
        else {
            devName.text = "<No Device Connected>"
        }
        // discover services/characteristics for device
        //
        services.removeAll()
        self.findActivity.startAnimating()
 
        // enumerate services
        thePeripheral?.discoverServices(nil)
        
        setupTextFields();
         
        // start polling status
        pollTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(pollStatus), userInfo: nil, repeats: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        pollTimer.invalidate()
    }
    
    override func didMove(toParent parent: UIViewController?) {
        if (parent == nil) {
            thePeripheral?.delegate = parentView as? CBPeripheralDelegate
        }
    }
    
    func setupTextFields() {
        let toolbar = UIToolbar()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                    target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .done,
                                    target: self, action: #selector(doneButtonTapped))
           
        toolbar.setItems([flexSpace, doneButton], animated: true)
        toolbar.sizeToFit()
               
        testResults.text = "not running"
        byteRate.text = "-"
    }
       
    @objc func doneButtonTapped() {
        view.endEditing(true)
    }

    @objc func pollStatus() {
        readDeviceStatus()
    }
    
    func readDeviceStatus() {
        let statusCharUUID = CBUUID.init(string:String(format:"%04X", LevelHomecharacteristicUUIDs.StatusCharacteristicShortID.rawValue))
        let consoleCharUUID = CBUUID.init(string:String(format:"%04X", LevelHomecharacteristicUUIDs.ConsoleCharacteristicShortID.rawValue))

        // find levelhome service in services list
        for lockdex in 0..<services.count {
            if services[lockdex].uuid == LevelHomeUUID {
                // find the console characteristic
                for chardex in 0..<characters[lockdex].count {
                    if (characters[lockdex][chardex].uuid == consoleCharUUID) {
                        writeValue(characters[lockdex][chardex], dataToWrite: "0123")
                        break;
                    }
                }
                // find lock current state char
                for chardex in 0..<characters[lockdex].count {
                    if (characters[lockdex][chardex].uuid == statusCharUUID) {
                        readValue(characters[lockdex][chardex])
                        return
                    }
                }
            }
        }
    }
    

    //MARK: CBPeripheralDelegate functions
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services! {
            print("  Discoserv \(utils.nameForService(uuid: service.uuid))")
            services += [service]
            DispatchQueue.main.async { () -> Void in
                self.findActivity.startAnimating()
                print( "Finding Characteristics for\(self.utils.nameForService(uuid: service.uuid))")
            }
            // enumerate chars
            characters += [[CBCharacteristic]()]
            thePeripheral?.discoverCharacteristics(nil, for: service)
        }
        DispatchQueue.main.async { () -> Void in
            self.findActivity.stopAnimating()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        let commandCharUUID = CBUUID.init(string:String(format:"%04X", LevelHomecharacteristicUUIDs.CommandCharacteristicShortID.rawValue))

        for ourservice in 0..<services.count {
            if service == services[ourservice] {
                var charindex = 0;
                
                for achar in service.characteristics! {
                    print("  serv\(ourservice) Discochar \(utils.nameForCharacteristic(uuid: achar.uuid))")
                    characters[ourservice] += [achar]
                    if achar.uuid == commandCharUUID {
                        cmdCharServiceIndex = ourservice;
                        cmdCharCharIndex = charindex;
                    }

                    DispatchQueue.main.async {
                        peripheral.discoverDescriptors(for: achar)
                    }
                    
                    charindex += 1
                }
                break;
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let descriptors = characteristic.descriptors {
            for desc in descriptors {
                if desc.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString {
                    peripheral.readValue(for: desc)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        DispatchQueue.main.async { () -> Void in
            //
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor: CBCharacteristic, error: Error?) {
        DispatchQueue.main.async { () -> Void in
            //
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let rv = utils.formatValue(for: characteristic)

        print("read uuid=\(characteristic.uuid) value=\(rv)")
        DispatchQueue.main.async { () -> Void in
            if rv != self.lastReadValue {
                var now : time_t = 0;
                
                time(&now);
                
                self.lastReadValue = rv
                self.testResults.text = rv
                
                // find byte in results inside ()
                if let bstart = rv.firstIndex(of: "(") {
                    if let bend   = rv.firstIndex(of: ")") {
                        let bytestr = rv[rv.index(after: bstart)..<bend]
                
                        if let bytecount = Int(bytestr) {
                            var delta = now - self.startTime;
                            
                            if (delta == 0) {
                                delta = 1;
                            }
                            
                            let bps = bytecount / delta;
                            let bpm = 60 * bps;
                            
                            var brstr : String = ""
                            
                            if (bpm > 0) {
                                brstr = String(format: "%d bytes/min", bpm)
                            } else {
                                brstr = String(format: "%d bytes/sec", bps)
                            }
                            self.byteRate.text = brstr
                        }
                    }
                }
            }
        }
    }

    //MARK: Control functions
    @IBAction func lightToggle(_ sender: Any) {
        if cmdCharServiceIndex >= 0 {
            let commandCharacteristic = characters[cmdCharServiceIndex][cmdCharCharIndex]

            writeValue(commandCharacteristic, dataToWrite: "zbs t")
        }
        else {
            print("No command Characteristic to send command to")
        }
    }
    
    @IBAction func onDisconnect(_ sender: Any) {
        pollTimer.invalidate()
        if thePeripheral != nil && centralMan != nil {
            centralMan!.cancelPeripheralConnection(thePeripheral!)
            navigationController?.popViewController(animated: true)
        }
    }
    
    //MARK: IO functions
    func readValue(_ characteristic: CBCharacteristic) {
        thePeripheral?.readValue(for: characteristic)
    }
    
    func writeValue(_ characteristic: CBCharacteristic, dataToWrite : String?) {
        // get value and convert to raw bytes
        if dataToWrite != nil {
            let bval = [UInt8](dataToWrite!.utf8)
            let dval = Data(bytes: bval, count: bval.count)
            thePeripheral?.writeValue(dval, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        }
    }
    
}
