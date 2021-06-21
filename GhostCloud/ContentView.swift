//
//  ContentView.swift
//  GhostCloud-macOS
//
//  Created by Alfred Neumayer on 17.06.21.
//

import SwiftUI
import FileProvider

enum ProviderType {
    case NextCloud
    case WebDav
}

struct Account {
    var host = ""
    var username = ""
    var password = ""
    var providerType : ProviderType = ProviderType.NextCloud
}

class FileProviderComm : NSObject, ObservableObject {
    @Published var isRegistered : Bool = false
    @Published var accounts : [Account] = []
    
    let defaultFileProviderDomain = NSFileProviderDomain(identifier:NSFileProviderDomainIdentifier("me.fredl.GhostCloud-macOS.FileProvider"), displayName: "GhostCloud");
    
    override init() {
        super.init()
        NSFileProviderManager.getDomainsWithCompletionHandler {(fileProviderDomain, error) in
            if (error != nil) {
                print("Error occured during getDomainsWithCompletionHandler: \(error as NSError?)")
            }
            print("Domain: \(self.defaultFileProviderDomain.identifier.rawValue)")
            for domain in fileProviderDomain {
                print("Domain: \(domain.identifier.rawValue)")
                if (domain.identifier.rawValue == self.defaultFileProviderDomain.identifier.rawValue) {
                    print("Is registered!");
                    self.isRegistered = true;
                }
            }
        }
    }
    
    func register() {
        NSFileProviderManager.add(defaultFileProviderDomain) { error in
            print("Add file provider domain: \(error as NSError?)")
            let manager = NSFileProviderManager(for: self.defaultFileProviderDomain)
            manager?.signalEnumerator(for: .rootContainer, completionHandler: { error in
                print("Signal change error: \(error as NSError?)")
            })
        }
    }
    
    func unregister() {
        NSFileProviderManager.remove(defaultFileProviderDomain) { error in
            
        }
    }

    func refreshAccounts() {
        
    }
}

extension View {
    @ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
        }
    }
}

public extension Color {
    static let backgroundColor = Color(NSColor.windowBackgroundColor)
    static let secondaryBackgroundColor = Color(NSColor.controlBackgroundColor)
}

public struct TabView : View {
    private let tabViews: [AnyView]
    
    @State var selection = 0
    
    public init(content: [(AnyView)]) {
        self.tabViews = content.map{ $0 }
    }

    var nextBar : some View {
        Button("Next") {
            selection += 1;
        }
        .padding([.leading, .trailing], 30)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            tabViews[selection]
                .padding(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(0)
        nextBar
    }
}

struct AddAccountSheet : View {
    @Binding var showModal: Bool
    @Binding var fileProviderComm : FileProviderComm
    @State var host : String = "https://"
    @State var username : String = ""
    @State var password : String = ""
    @State private var selectedLoginType = 0

    var loginTypes = ["NextCloud",
                      "NextCloud (app password)",
                      "WebDav"]

    func dismiss() {
        showModal = false
    }

    var body: some View {
        let tabView = TabView (
            content: [
                (
                    AnyView(
                        VStack {
                            Button(action: {
                                dismiss()
                            }) {
                                Image (systemName: "xmark.circle").renderingMode(.original)
                            }.position(x: 20, y: 20).buttonStyle(PlainButtonStyle())
                            
                            VStack(alignment: .leading) {
                                Picker(selection: $selectedLoginType, label: Text("Select your cloud")) {
                                    ForEach(0..<loginTypes.count) {
                                        Text(self.loginTypes[$0])
                                    }
                                }
                            }.padding(100)
                        }
                    )
                ),
                (
                    AnyView(
                        VStack {
                            Button(action: {
                                dismiss()
                            }) {
                                Image (systemName: "xmark.circle").renderingMode(.original)
                            }.position(x: 20, y: 20).buttonStyle(PlainButtonStyle())
                            
                            VStack(alignment: .leading) {
                                TextField("Host", text: $host)
                                TextField("Username", text: $username)
                                TextField("Password", text: $password)
                            }.padding(100)
                            
                            Button("Add account") {
                                fileProviderComm.register()
                                dismiss()
                            }
                            .padding()
                        }
                    )
                )
            ]
        )
        tabView
    }
}

struct Sidebar: View {
    var body: some View {
        List {
            
        }.listStyle(SidebarListStyle())
    }
}

struct ContentView: View {
    @State private var hasAccount = false;
    @State private var isRegistered = false;
    @State private var showingAccountSheet = false
    @State private var fileProviderComm : FileProviderComm;
    
    init() {
        fileProviderComm = FileProviderComm()
    }
    
    var body: some View {
        NavigationView {
            Sidebar().isHidden(!hasAccount, remove: true)
            Text("Please add an account to continue").font(.system(size: 24)).padding().isHidden(hasAccount, remove: true)
        }
        .navigationTitle("GhostCloud")
        .toolbar {
            Button ("Add account") {
                showingAccountSheet.toggle()
            }
            .sheet(isPresented: $showingAccountSheet) {
                AddAccountSheet(showModal: $showingAccountSheet, fileProviderComm: $fileProviderComm).frame(minWidth: 450, idealWidth: 450, maxWidth: 450, minHeight: 400, idealHeight: 400, maxHeight: 400, alignment: .center)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
