import Foundation

enum JXAScripts {
    /// Returns JSON:
    /// { "accountCount": number, "folderCount": number }
    static let testConnection: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;
    try { Notes.launch(); } catch (e) {}

    var accounts = safeCall(function(){ return Notes.accounts(); }, []);
    var accountCount = accounts.length;
    var folderCount = 0;
    for (var a = 0; a < accounts.length; a++) {
      var fs = safeCall(function(){ return accounts[a].folders(); }, []);
      folderCount += fs.length;
    }

    JSON.stringify({ accountCount: accountCount, folderCount: folderCount });
    """

    /// Diagnostics-only JSON (never used for model decoding):
    /// {
    ///   "notesRunning": bool?,
    ///   "accountsCount": number?,
    ///   "foldersCount": number?,
    ///   "errors": [string]
    /// }
    static let diagnosticsProbe: String = """
    ObjC.import('Foundation');

    function toStr(e) { try { return String(e); } catch (_) { return "unknown_error"; } }

    var out = { notesRunning: null, accountsCount: null, foldersCount: null, errors: [] };

    try {
      var Notes = Application("Notes");
      Notes.includeStandardAdditions = true;
      try { out.notesRunning = Notes.running(); } catch (e) { out.errors.push("Notes.running error: " + toStr(e)); }
      try { Notes.launch(); } catch (e) { out.errors.push("Notes.launch error: " + toStr(e)); }
      try { Notes.activate(); } catch (e) { out.errors.push("Notes.activate error: " + toStr(e)); }

      var accounts = null;
      try { accounts = Notes.accounts(); } catch (e) { out.errors.push("Notes.accounts error: " + toStr(e)); accounts = []; }
      out.accountsCount = accounts.length;

      var foldersCount = 0;
      for (var a = 0; a < accounts.length; a++) {
        try {
          var fs = accounts[a].folders();
          foldersCount += fs.length;
        } catch (e) {
          out.errors.push("account[" + a + "].folders error: " + toStr(e));
        }
      }
      out.foldersCount = foldersCount;
    } catch (e) {
      out.errors.push("Notes app error: " + toStr(e));
    }

    JSON.stringify(out);
    """

    /// Returns JSON:
    /// { "counts": [ { "folderId": "string", "noteCount": number } ] }
    static let listFolderNoteCounts: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }
    function safeString(v) { return (v === null || v === undefined) ? "" : String(v); }

    function stableID(obj, fallback) {
      try {
        var v = obj.id();
        if (v) return String(v);
      } catch (e) {}
      return fallback;
    }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;
    try { Notes.launch(); } catch (e) {}

    var accounts = safeCall(function(){ return Notes.accounts(); }, []);
    var out = { counts: [] };

    for (var a = 0; a < accounts.length; a++) {
      var acct = accounts[a];
      var acctName = safeString(safeCall(function(){ return acct.name(); }, "Account"));
      var folders = safeCall(function(){ return acct.folders(); }, []);
      for (var f = 0; f < folders.length; f++) {
        var folder = folders[f];
        var id = stableID(folder, "folder|" + acctName + "|" + f);
        var n = 0;
        try {
          var notes = safeCall(function(){ return folder.notes(); }, []);
          n = notes.length;
        } catch (e) { n = 0; }
        out.counts.push({ folderId: id, noteCount: n });
      }
    }

    JSON.stringify(out);
    """

    /// Returns JSON:
    /// { "accounts": [ { "id": "...", "name": "...", "folders": [ { "id": "...", "name": "...", "path": "Account/Foo/Bar" } ] } ] }
    static let listAccountsAndFolders: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }
    function safeString(v) { return (v === null || v === undefined) ? "" : String(v); }
    function iso(d) { try { return d ? new Date(d).toISOString() : null; } catch (e) { return null; } }

    function stableID(obj, fallback) {
      try {
        var v = obj.id();
        if (v) return String(v);
      } catch (e) {}
      return fallback;
    }

    function folderPathComponents(folder) {
      var parts = [];
      var cur = folder;
      var guardCount = 0;
      while (cur && guardCount < 64) {
        guardCount++;
        var name = safeString(safeCall(function(){ return cur.name(); }, ""));
        if (name) parts.unshift(name);
        // parent folder (may throw)
        cur = safeCall(function(){ return cur.folder(); }, null);
      }
      return parts;
    }

    function walkFolder(folder, accountName, out) {
      var parts = folderPathComponents(folder);
      var name = parts.length ? parts[parts.length - 1] : safeString(safeCall(function(){ return folder.name(); }, ""));
      var path = accountName + "/" + parts.join("/");
      var id = stableID(folder, "folder|" + accountName + "|" + parts.join("|"));
      out.push({ id: id, name: name || "Untitled Folder", path: path });

      var children = safeCall(function(){ return folder.folders(); }, []);
      for (var i = 0; i < children.length; i++) {
        walkFolder(children[i], accountName, out);
      }
    }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;
    try { Notes.launch(); } catch (e) {}

    var accounts = safeCall(function(){ return Notes.accounts(); }, []);
    var outAccounts = [];

    for (var a = 0; a < accounts.length; a++) {
      var acct = accounts[a];
      var acctName = safeString(safeCall(function(){ return acct.name(); }, "Account"));
      var acctID = stableID(acct, "account|" + acctName);

      var foldersOut = [];
      // Prefer a root-only traversal (folders without a parent) to preserve hierarchy.
      var topFolders = safeCall(function(){ return acct.folders(); }, []);
      for (var f = 0; f < topFolders.length; f++) {
        var folder = topFolders[f];
        var hasParent = false;
        try { hasParent = !!folder.folder(); } catch (e) { hasParent = false; }
        if (!hasParent) {
          walkFolder(folder, acctName, foldersOut);
        }
      }

      outAccounts.push({ id: acctID, name: acctName, folders: foldersOut });
    }

    JSON.stringify({ accounts: outAccounts });
    """

    /// Template expects one placeholder: folderID JS string literal.
    /// Returns JSON:
    /// { "folderId": "...", "notes": [ { "id": "...", "title": "...", "createdAt": "...?", "modifiedAt": "...?" } ] }
    static let listNotesInFolderTemplate: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }
    function safeString(v) { return (v === null || v === undefined) ? "" : String(v); }
    function iso(d) { try { return d ? new Date(d).toISOString() : null; } catch (e) { return null; } }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;

    var folderID = %@;

    function allFolders() {
      var accts = safeCall(function(){ return Notes.accounts(); }, []);
      var res = [];
      for (var a = 0; a < accts.length; a++) {
        var fs = safeCall(function(){ return accts[a].folders(); }, []);
        for (var i = 0; i < fs.length; i++) { res.push(fs[i]); }
      }
      return res;
    }

    function matchFolderByID(targetID) {
      var fs = allFolders();
      for (var i = 0; i < fs.length; i++) {
        try { if (String(fs[i].id()) === targetID) { return fs[i]; } } catch (e) {}
      }
      return null;
    }

    var folder = matchFolderByID(folderID);
    var out = { folderId: String(folderID), notes: [] };
    if (folder) {
      var notes = safeCall(function(){ return folder.notes(); }, []);
      for (var n = 0; n < notes.length; n++) {
        var note = notes[n];
        var id = safeString(safeCall(function(){ return note.id(); }, ""));
        var title = safeString(safeCall(function(){ return note.name(); }, "Untitled"));
        var createdAt = iso(safeCall(function(){ return note.creationDate(); }, null));
        var modifiedAt = iso(safeCall(function(){ return note.modificationDate(); }, null));
        out.notes.push({ id: id, title: title, createdAt: createdAt, modifiedAt: modifiedAt });
      }
    }
    JSON.stringify(out);
    """

    /// Template expects one placeholder: noteID JS string literal.
    /// Returns JSON:
    /// { id, title, account?, folderPath?, createdAt?, modifiedAt?, html?, plain?, hasAttachments }
    static let getNoteDetailTemplate: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }
    function safeString(v) { return (v === null || v === undefined) ? "" : String(v); }
    function iso(d) { try { return d ? new Date(d).toISOString() : null; } catch (e) { return null; } }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;

    var noteID = %@;

    var out = {
      id: String(noteID),
      title: "",
      account: null,
      folderPath: null,
      createdAt: null,
      modifiedAt: null,
      html: null,
      plain: null,
      hasAttachments: false
    };

    function tryHTML(note) {
      // Notes versions vary; we try a few approaches and keep stdout JSON-only.
      var body = safeCall(function(){ return note.body(); }, null);
      if (body === null || body === undefined) return null;

      if (typeof body === 'string') {
        if (body.indexOf('<') >= 0 && body.indexOf('>') >= 0) return body;
        return null;
      }

      // Some JXA bridge objects expose html()/toString().
      try {
        if (typeof body.html === 'function') {
          var h = body.html();
          if (h && typeof h === 'string') return h;
        }
      } catch (e) {}

      try {
        var s = body.toString();
        if (s && typeof s === 'string' && s.indexOf('<') >= 0 && s.indexOf('>') >= 0) return s;
      } catch (e) {}

      return null;
    }

    function folderPath(folder) {
      if (!folder) return null;
      var parts = [];
      var cur = folder;
      var guardCount = 0;
      while (cur && guardCount < 64) {
        guardCount++;
        var name = safeString(safeCall(function(){ return cur.name(); }, ""));
        if (name) parts.unshift(name);
        cur = safeCall(function(){ return cur.folder(); }, null);
      }
      return parts.join('/');
    }

    try {
      function findNoteById(id) {
        try { return Notes.notes.byId(id); } catch (e) {}
        try { return Notes.note({ id: id }); } catch (e) {}
        return null;
      }
      var note = findNoteById(noteID);
      if (!note) throw "note_not_found";

      out.title = safeString(safeCall(function(){ return note.name(); }, "Untitled"));
      out.createdAt = iso(safeCall(function(){ return note.creationDate(); }, null));
      out.modifiedAt = iso(safeCall(function(){ return note.modificationDate(); }, null));

      // Plain text:
      var plain = safeCall(function(){ return note.plaintext(); }, null);
      if (plain === null || plain === undefined) {
        plain = safeCall(function(){ return note.plainText(); }, null);
      }
      out.plain = (plain === null || plain === undefined) ? null : safeString(plain);

      // HTML:
      out.html = tryHTML(note);

      // Container (folder) + account best-effort:
      var folder = safeCall(function(){ return note.container(); }, null);
      if (!folder) folder = safeCall(function(){ return note.folder(); }, null);
      out.folderPath = folderPath(folder);

      var acct = safeCall(function(){ return folder ? folder.account() : null; }, null);
      out.account = acct ? safeString(safeCall(function(){ return acct.name(); }, null)) : null;

      // Attachments:
      var atts = safeCall(function(){ return note.attachments(); }, []);
      out.hasAttachments = (atts && atts.length && atts.length > 0) ? true : false;
    } catch (e) {
      // Keep partial out; process still exits successfully.
      if (!out.title) out.title = "Untitled";
      if (out.plain === null) out.plain = "";
      out.html = null;
      out.hasAttachments = false;
    }

    JSON.stringify(out);
    """

    /// Template expects 3 placeholders:
    /// 1) noteID JS string literal
    /// 2) destDir POSIX path JS string literal
    /// 3) noteSlug JS string literal
    ///
    /// Writes files to `destDir` and returns JSON:
    /// { "noteId": "...", "exports": [ { kind, mimeType?, relativePath, originalName? } ], "errors": [ { message, code? } ] }
    static let exportAttachmentsTemplate: String = """
    ObjC.import('Foundation');

    function isAuthError(e) {
      var s = "";
      try { s = String(e); } catch (_) { s = ""; }
      s = s.toLowerCase();
      return (s.indexOf("-1743") >= 0) || (s.indexOf("not authorized") >= 0) || (s.indexOf("not authorised") >= 0);
    }
    function safeCall(fn, fallback) { try { return fn(); } catch (e) { if (isAuthError(e)) { throw e; } return fallback; } }
    function safeString(v) { return (v === null || v === undefined) ? "" : String(v); }

    var Notes = Application("Notes");
    Notes.includeStandardAdditions = true;

    var noteID = %@;
    var destDir = %@;
    var noteSlug = %@;

    var out = { noteId: String(noteID), exports: [], errors: [] };

    function ensureDir(path) {
      var fm = $.NSFileManager.defaultManager;
      var isDir = Ref();
      var ok = fm.fileExistsAtPathIsDirectory($(path), isDir);
      if (ok && isDir[0]) return;
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(path), true, $(), null);
    }

    function extForMime(mime) {
      if (!mime) return null;
      var m = String(mime).toLowerCase();
      if (m.indexOf("image/png") === 0) return "png";
      if (m.indexOf("image/jpeg") === 0) return "jpg";
      if (m.indexOf("image/jpg") === 0) return "jpg";
      if (m.indexOf("image/gif") === 0) return "gif";
      if (m.indexOf("image/heic") === 0) return "heic";
      if (m.indexOf("image/heif") === 0) return "heif";
      if (m.indexOf("image/tiff") === 0) return "tiff";
      if (m.indexOf("application/pdf") === 0) return "pdf";
      if (m.indexOf("text/plain") === 0) return "txt";
      return null;
    }

    function pathExtFromName(name) {
      if (!name) return null;
      var s = String(name);
      var idx = s.lastIndexOf('.');
      if (idx < 0 || idx === s.length - 1) return null;
      return s.substring(idx + 1).toLowerCase();
    }

    function uniquePath(basePath) {
      var fm = $.NSFileManager.defaultManager;
      if (!fm.fileExistsAtPath($(basePath))) return basePath;
      var dot = basePath.lastIndexOf('.');
      var stem = (dot >= 0) ? basePath.substring(0, dot) : basePath;
      var ext = (dot >= 0) ? basePath.substring(dot) : "";
      for (var i = 2; i < 10_000; i++) {
        var candidate = stem + "_" + i + ext;
        if (!fm.fileExistsAtPath($(candidate))) return candidate;
      }
      return stem + "_" + (new Date().getTime()) + ext;
    }

    function writeNSData(data, path) {
      try {
        var nsdata = data;
        if (nsdata && nsdata.js) nsdata = nsdata.js;
        if (nsdata && nsdata.writeToFileAtomically) {
          return nsdata.writeToFileAtomically($(path), true);
        }
        // Some bridges provide bytes as ObjC object; try converting.
        var wrapped = ObjC.wrap(nsdata);
        if (wrapped && wrapped.writeToFileAtomically) {
          return wrapped.writeToFileAtomically($(path), true);
        }
      } catch (e) {}
      return false;
    }

    function sanitizeRel(p) {
      // relativePath is always "assets/<noteSlug>/<filename>"
      return "assets/" + noteSlug + "/" + p;
    }

    try {
      ensureDir(destDir);
      function findNoteById(id) {
        try { return Notes.notes.byId(id); } catch (e) {}
        try { return Notes.note({ id: id }); } catch (e) {}
        return null;
      }
      var note = findNoteById(noteID);
      if (!note) throw "note_not_found";
      var atts = safeCall(function(){ return note.attachments(); }, []);
      for (var i = 0; i < atts.length; i++) {
        var att = atts[i];
        try {
          var originalName = safeString(safeCall(function(){ return att.name(); }, "")) || null;
          var mime = safeCall(function(){ return att.mimeType(); }, null);
          if (!mime) mime = safeCall(function(){ return att.typeIdentifier(); }, null);

          var ext = pathExtFromName(originalName) || extForMime(mime) || "bin";
          var kind = (mime && String(mime).toLowerCase().indexOf("image/") === 0) ? "image" : "file";

          var filename = noteSlug + "_" + (i + 1) + "." + ext;
          var absPath = destDir + "/" + filename;
          absPath = uniquePath(absPath);
          var finalName = absPath.substring(absPath.lastIndexOf("/") + 1);

          var data = safeCall(function(){ return att.data(); }, null);
          if (!data) {
            // Some attachments expose "content" instead.
            data = safeCall(function(){ return att.content(); }, null);
          }

          if (!data) {
            out.errors.push({ message: "Attachment had no exportable data.", code: "no_data" });
            continue;
          }

          var ok = writeNSData(data, absPath);
          if (!ok) {
            out.errors.push({ message: "Failed to write attachment to disk.", code: "write_failed" });
            continue;
          }

          out.exports.push({
            kind: kind,
            mimeType: mime ? String(mime) : null,
            relativePath: sanitizeRel(finalName),
            originalName: originalName
          });
        } catch (e) {
          out.errors.push({ message: "Attachment export failed: " + String(e), code: "exception" });
        }
      }
    } catch (e) {
      out.errors.push({ message: "Attachment export failed: " + String(e), code: "exception" });
    }

    JSON.stringify(out);
    """
}

extension String {
    /// JS string literal quoting (for script templates).
    var jsQuoted: String {
        "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

