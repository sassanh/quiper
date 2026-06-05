# Touch ID & Data Security

Quiper includes a native biometric encryption system called **Biometric Secure Sandboxing**. This feature is designed to protect highly sensitive chat sessions, cookies, caches, and logs from local access or theft, requiring Touch ID (or your system password) to unlock them.

---

## Technical Architecture

When you lock an engine behind Touch ID, Quiper isolates its entire browser database on your Mac’s disk using native macOS storage and cryptography tools:

```
  +──────────────────────────────────────────────────────────+
  |                   WebKit WebsiteDataStore                |
  |  ~/Library/WebKit/app.sassanh.quiper.Quiper/             |
  +────────────────────────────┬─────────────────────────────+
                               │
               [ Dynamically Mounted Over Path ]
                               │
  +────────────────────────────▼─────────────────────────────+
  |              Encrypted APFS SparseBundle                 |
  |  AES-256 Encrypted via hdiutil & Unlocked by Touch ID     |
  +──────────────────────────────────────────────────────────+
```

### 1. The APFS Sparsebundle
*   **Creation:** When you enable encryption for a service, Quiper runs macOS's native disk utility:
    ```bash
    hdiutil create -size 5g -fs APFS -encryption AES-256 -volname QuiperEngine-[ServiceID] -type SPARSEBUNDLE -stdinpass [BundlePath]
    ```
*   **Size:** The bundle is initialized with a maximum virtual size of 5 GB, but as a "sparsebundle," it only occupies the actual size of the files on your physical disk (usually a few megabytes initially).
*   **Location:** Sparsebundles are stored under:
    `~/Library/Application Support/app.sassanh.quiper.Quiper/EncryptedStores/[ServiceID].sparsebundle`

### 2. The Keychain Passphrase
*   A secure, random 64-character passphrase is generated to encrypt the sparsebundle.
*   This passphrase is saved directly in your **macOS Keychain** under an ACL (Access Control List) restriction. The key can only be read by Quiper, and only after a successful biometric authentication request.

### 3. Dynamic WebKit Overlay Mounting
WebKit stores website databases (cookies, localStorage, IndexedDB databases, HTTP cache, and session state) in a designated directory on your system. 

When you unlock a service:
1.  Quiper requests Touch ID authentication.
2.  Upon verification, it retrieves the passphrase from the Keychain.
3.  Quiper mounts the sparsebundle directly over the WebKit cache folder for that specific service ID:
    *   **Mount Point:** `~/Library/WebKit/app.sassanh.quiper.Quiper/WebsiteDataStore/[service-id-lowercase]/`
    *   **Attach Command:**
        ```bash
        hdiutil attach -nobrowse -mountpoint [MountPoint] -stdinpass [BundlePath]
        ```
4.  WebKit writes cookies and cache directly into this mounted directory. To the operating system, it looks like a standard folder, but the underlying blocks are written directly into the AES-256 encrypted sparsebundle.

### 4. Auto-Lock & Unmounting
When you lock the engine, Quiper terminates the active web views (wiping their memory states) and detaches the disk image:
```bash
hdiutil detach -force [MountPoint]
```
The mount directory is then removed. The files become unreadable blocks of encrypted ciphertext until the next Touch ID authorization.

---

## Lock Policies

You can configure when Quiper locks your encrypted engines in **Settings (`⌘ ,`) ➔ Engines**:

1.  **Lock on Switch Away (Recommended):** The volume is immediately unmounted the moment you click away to another engine slot or minimize the Quiper window.
2.  **Lock on Inactivity Timeout:** Keeps the volume mounted as long as you are active. If no mouse movement or keypresses are detected within your configured timeout (e.g. 5 minutes), the session is torn down and unmounted.
3.  **Manual Lock:** Click the lock icon in the session header bar to lock the slot immediately.

---

## Local Threat Model Boundaries

### What it Protects Against (Scope)
*   **Device Theft:** If your Mac is stolen while locked or powered off, your secure Quiper session logs, cache files, and active session cookies cannot be extracted from the disk.
*   **Shared Computers / Local Snooping:** Other users logging into your computer (or accessing it while you step away) cannot read your chats or inherit your logged-in sessions without your fingerprint.

### What it Does NOT Protect Against (Out of Scope)
*   **Transit Security:** Secure Sandboxing only protects data *at rest on your local Mac*. 
*   **Cloud Provider Servers:** Your prompts are still transmitted to the cloud servers of OpenAI, Google, Anthropic, or whoever runs the destination service. They are processed according to the respective provider's terms of service and are not protected by local APFS encryption once sent.
