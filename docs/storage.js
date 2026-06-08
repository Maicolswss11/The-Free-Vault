const VaultDB = (() => {
  const DB_NAME = "the-free-vault";
  const DB_VERSION = 1;
  const STORE_NAME = "settings";
  const LIBRARY_RECORD = "library";
  const LEGACY_KEY = "the-free-vault-library-v2";

  function openDatabase() {
    return new Promise((resolve, reject) => {
      if (!("indexedDB" in window)) {
        reject(new Error("IndexedDB non supportato"));
        return;
      }

      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          db.createObjectStore(STORE_NAME);
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error("Apertura IndexedDB fallita"));
    });
  }

  async function readRecord(key) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE_NAME, "readonly");
      const request = transaction.objectStore(STORE_NAME).get(key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => db.close();
    });
  }

  async function writeRecord(key, value) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE_NAME, "readwrite");
      transaction.objectStore(STORE_NAME).put(value, key);
      transaction.oncomplete = () => {
        db.close();
        resolve();
      };
      transaction.onerror = () => {
        db.close();
        reject(transaction.error);
      };
    });
  }

  function readLegacyLibrary() {
    try {
      const parsed = JSON.parse(localStorage.getItem(LEGACY_KEY) || "{}");
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
    } catch {
      return {};
    }
  }

  async function loadLibrary() {
    try {
      const stored = await readRecord(LIBRARY_RECORD);
      if (stored && typeof stored === "object" && !Array.isArray(stored)) {
        return stored;
      }

      const legacy = readLegacyLibrary();
      if (Object.keys(legacy).length) {
        await writeRecord(LIBRARY_RECORD, legacy);
        localStorage.removeItem(LEGACY_KEY);
      }
      return legacy;
    } catch (error) {
      console.warn("IndexedDB non disponibile, uso localStorage.", error);
      return readLegacyLibrary();
    }
  }

  async function saveLibrary(library) {
    try {
      await writeRecord(LIBRARY_RECORD, library);
      localStorage.removeItem(LEGACY_KEY);
    } catch (error) {
      console.warn("Salvataggio IndexedDB fallito, uso localStorage.", error);
      localStorage.setItem(LEGACY_KEY, JSON.stringify(library));
    }
  }

  return Object.freeze({ loadLibrary, saveLibrary });
})();
