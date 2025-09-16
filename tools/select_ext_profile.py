import glob,plistlib,subprocess,os,sys,shlex,tempfile
def decode(path):
    t=tempfile.NamedTemporaryFile(suffix=".plist",delete=False).name
    try:
        subprocess.check_call(["/usr/bin/security","cms","-D","-i",path,"-o",t],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        with open(t,"rb") as f: return plistlib.load(f)
    except Exception: return None
    finally:
        try: os.unlink(t)
        except Exception: pass

cands=[]
for f in glob.glob(os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision")):
    d=decode(f)
    if not d: continue
    ent=d.get("Entitlements",{})
    exts=ent.get("com.apple.developer.extensionkit.extension-point-identifiers") or []
    if "com.apple.Safari.web-extension" not in exts: continue
    appid=ent.get("application-identifier","")
    team=(d.get("TeamIdentifier") or [""])[0] or (d.get("ApplicationIdentifierPrefix") or [""])[0]
    bid=appid.split(".",1)[1] if "." in appid else ""
    cands.append({"name":d.get("Name") or "", "uuid":d.get("UUID") or "", "team":team or "", "bundle_id":bid, "path":f})

if not cands:
    print("NO_PROFILE_WITH_SAFARI_EXTENSION_ENTITLEMENT")
    sys.exit(2)

best=cands[0]
with open(".provtmp/sel.env","w") as w:
    w.write("export NAME=%s\n" % shlex.quote(best["name"]))
    w.write("export UUID=%s\n" % shlex.quote(best["uuid"]))
    w.write("export TEAM=%s\n" % shlex.quote(best["team"]))
    w.write("export BUNDLE_ID=%s\n" % shlex.quote(best["bundle_id"]))
print(best["name"]); print(best["uuid"]); print(best["team"]); print(best["bundle_id"])
