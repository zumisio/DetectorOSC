import SwiftUI
import UIKit

struct OSCSettingsView: View {
    @ObservedObject var oscManager: OSCManager
    @State private var ipAddress: String
    @State private var port: String
    @State private var showingAlert = false
    @State private var alertMessage = ""

    init(oscManager: OSCManager) {
        self.oscManager = oscManager
        _ipAddress = State(initialValue: oscManager.ipAddress)
        _port = State(initialValue: String(oscManager.port))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text("IP Address:")
                            .frame(width: 90, alignment: .leading)
                        TextField("", text: $ipAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .frame(width: 120)
                            .textFieldStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    HStack(spacing: 8) {
                        Text("Port:")
                            .frame(width: 40, alignment: .leading)
                        TextField("", text: $port)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .textFieldStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button("Update Settings") {
                        updateSettings()
                    }
                    .frame(maxWidth: .infinity)
                    //.buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func updateSettings() {
        // Validate IP address format
        let ipAddressRegex = #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        let ipAddressTest = NSPredicate(format:"SELF MATCHES %@", ipAddressRegex)
        
        if !ipAddressTest.evaluate(with: ipAddress) {
            alertMessage = "Invalid IP address format"
            showingAlert = true
            return
        }
        
        guard let portNumber = UInt16(port) else {
            alertMessage = "Invalid port number"
            showingAlert = true
            return
        }
        
        oscManager.updateSettings(ipAddress: ipAddress, port: portNumber)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

