from playwright.sync_api import sync_playwright
T={'light':dict(canvas='#ECECEA',bg='#FFFFFF',side='#F7F7F5',text='#1A1A1A',sec='#6B6B68',ter='#9C9C98',border='#E7E7E4',fborder='#DCDCD8',field='#FFFFFF',focus='#A8A8A4',ring='rgba(26,26,26,0.08)',track='#F1F1EE',seg='#FFFFFF',pbg='#1A1A1A',pfg='#FFFFFF',sbg='#FFFFFF',sborder='#DCDCD8',sfg='#1A1A1A',hover='#F2F2EF',sel='#ECECE9',shadow='0 1px 2px rgba(0,0,0,.04),0 12px 40px rgba(0,0,0,.10)',segsh='0 1px 2px rgba(0,0,0,.08),0 0 0 .5px rgba(0,0,0,.06)',avatar='#EFEFEC',traffic='#DCDCD8'),
'dark':dict(canvas='#0F0F11',bg='#1C1D20',side='#18191B',text='#F3F4F6',sec='#9A9CA2',ter='#6C6E75',border='#2A2B2F',fborder='#323338',field='#222326',focus='#5E6067',ring='rgba(243,244,246,0.08)',track='#26272B',seg='#36373C',pbg='#F3F4F6',pfg='#1C1D20',sbg='#26272B',sborder='#34353A',sfg='#F3F4F6',hover='#232427',sel='#2A2B2F',shadow='0 0 0 .5px rgba(255,255,255,.06),0 16px 48px rgba(0,0,0,.5)',segsh='0 1px 2px rgba(0,0,0,.3)',avatar='#2A2B2F',traffic='#3A3B40')}
import base64
# SF Pro through the system font: text in SF Pro, titles in SF Pro Rounded Semibold. Nothing is embedded.
CSS='''*{box-sizing:border-box;margin:0}body{background:VAR(canvas);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;color:VAR(text);-webkit-font-smoothing:antialiased;font-size:13px;letter-spacing:-.003em}
.stage{display:inline-flex;gap:40px;padding:56px;align-items:flex-start}
.sheet{width:440px;background:VAR(bg);border-radius:14px;box-shadow:VAR(shadow);padding:20px 24px 24px}
.hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
h1{font-family:ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,system-ui,sans-serif;font-size:15px;font-weight:600;letter-spacing:-.01em}
.x{width:24px;height:24px;border-radius:6px;display:grid;place-items:center;color:VAR(ter)}
.lbl{font-size:12px;font-weight:400;color:VAR(sec);margin-bottom:6px;display:block}
.field{height:32px;border:1px solid VAR(fborder);background:VAR(field);border-radius:8px;padding:0 10px;display:flex;align-items:center;gap:8px;font-size:13px}
.field.focus{border-color:VAR(focus);box-shadow:0 0 0 3px VAR(ring)}
.ph{color:VAR(ter)}.mono{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;font-size:12px;font-variant-numeric:tabular-nums}
.grp{margin-bottom:20px}
.seg{display:flex;background:VAR(track);border-radius:8px;padding:2px;height:32px}
.seg div{flex:1;display:grid;place-items:center;border-radius:6px;font-size:13px;color:VAR(sec);font-weight:400}
.seg .on{background:VAR(seg);color:VAR(text);box-shadow:VAR(segsh)}
.help{font-size:12px;color:VAR(sec);line-height:1.5;margin-top:8px}
.ft{display:flex;justify-content:flex-end;gap:8px;margin-top:28px}
.btn{height:28px;padding:0 14px;border-radius:8px;font-size:13px;font-weight:400;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
.p{background:VAR(pbg);color:VAR(pfg)}.s{background:VAR(sbg);color:VAR(sfg);box-shadow:inset 0 0 0 1px VAR(sborder)}
.q{color:VAR(sec);font-size:12px;font-weight:400;padding:0 8px;height:24px;border-radius:6px;display:inline-flex;align-items:center}
.row{display:flex;gap:8px}.row .field{flex:1;min-width:0}.row .btn{width:72px;justify-content:center;flex:none}
.sub{font-size:13px;color:VAR(sec);margin:-12px 0 20px;line-height:1.5}
.meta{display:flex;align-items:center;gap:6px;font-size:12px;color:VAR(ter);margin-top:4px}
.icon{flex:none;width:14px;height:14px;stroke:currentColor;fill:none;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.cap{font-size:11px;color:VAR(ter);margin:0 0 10px 4px;font-weight:400}
.win{width:720px;height:520px;background:VAR(bg);border-radius:12px;box-shadow:VAR(shadow);display:flex;overflow:hidden}
.sb{width:188px;background:VAR(side);padding:14px 10px;border-right:1px solid VAR(border)}
.tl{display:flex;gap:8px;padding:2px 6px 22px}.tl i{width:12px;height:12px;border-radius:50%;background:VAR(traffic)}
.tab{height:30px;display:flex;align-items:center;gap:10px;padding:0 10px;border-radius:7px;color:VAR(sec);font-weight:400;margin-bottom:2px}
.tab.on{background:VAR(sel);color:VAR(text)}
.main{flex:1;padding:44px 40px}
h2{font-family:ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,system-ui,sans-serif;font-size:20px;font-weight:600;letter-spacing:-.02em;margin-bottom:4px}
.desc{color:VAR(sec);margin-bottom:36px}
.sh{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}
h3{font-family:ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,system-ui,sans-serif;font-size:13px;font-weight:600}
.person{display:flex;align-items:center;gap:12px;height:52px;padding:0 12px;margin:0 -12px;border-radius:10px}
.person.hv{background:VAR(hover)}
.av{width:30px;height:30px;border-radius:50%;background:VAR(avatar);display:grid;place-items:center;font-size:12px;font-weight:700;color:VAR(sec)}
.who{flex:1}.who b{font-weight:400;display:block}.who span{font-size:12px;color:VAR(ter)}
.role{font-size:12px;color:VAR(sec)}
.dot{width:5px;height:5px;border-radius:50%;background:VAR(ter);display:inline-block}
.foot{margin-top:32px;font-size:12px;color:VAR(ter);line-height:1.5}
'''
def ic(d):return f'<svg class="icon" viewBox="0 0 16 16">{d}</svg>'
X=ic('<path d="M4 4l8 8M12 4l-8 8"/>');COPY=ic('<rect x="5.5" y="5.5" width="8" height="8" rx="2"/><path d="M10.5 3.5v-.5a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5"/>')
EYE=ic('<path d="M1.5 8S4 3.5 8 3.5 14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"/><circle cx="8" cy="8" r="2"/>')
CLK=ic('<circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1.5"/>');PLUS=ic('<path d="M8 3.5v9M3.5 8h9"/>')
def invite():return f'''<div class="stage"><div><div class="cap">1 · Invite</div><div class="sheet"><div class="hd"><h1>Invite</h1><div class="x">{X}</div></div>
<div class="grp"><label class="lbl">Email</label><div class="field focus"><span class="ph">name@company.com</span></div></div>
<div><label class="lbl">Role</label><div class="seg"><div class="on">Member</div><div>Admin</div></div>
<p class="help">Members can add and edit. Admins can also invite and manage people.</p></div>
<div class="ft"><span class="btn s">Cancel</span><span class="btn p">Create invite</span></div></div></div>
<div><div class="cap">2 · Share</div><div class="sheet"><div class="hd"><h1>Share invite</h1><div class="x">{X}</div></div>
<p class="sub">Send the link, then share the code separately.</p>
<div class="grp"><label class="lbl">Link</label><div class="row"><div class="field"><span class="mono" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">https://grails.arjoon.xyz/i/k3x9Qa2mPz7L</span></div><span class="btn s" style="height:32px">{COPY}Copy</span></div></div>
<div class="grp"><label class="lbl">Code</label><div class="row"><div class="field" style="justify-content:space-between"><span class="mono" style="font-size:15px;font-weight:400">482 917</span><span style="color:VAR(ter);display:flex">{EYE}</span></div><span class="btn s" style="height:32px">{COPY}Copy</span></div></div>
<div class="meta">{CLK}Expires in 24 hours</div>
<div class="ft"><span class="btn p">Done</span></div></div></div></div>'''
GEN=ic('<circle cx="8" cy="8" r="2"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"/>')
LIB=ic('<rect x="2" y="2.5" width="5" height="5" rx="1"/><rect x="9" y="2.5" width="5" height="5" rx="1"/><rect x="2" y="9.5" width="5" height="5" rx="1"/><rect x="9" y="9.5" width="5" height="5" rx="1"/>')
TEAM=ic('<circle cx="6" cy="5.5" r="2.3"/><path d="M1.8 13.5c.5-2.3 2.2-3.5 4.2-3.5s3.7 1.2 4.2 3.5"/><circle cx="11.5" cy="6" r="1.8"/><path d="M11.5 10c1.5 0 2.5.9 2.8 2.7"/>')
STO=ic('<ellipse cx="8" cy="4" rx="5.5" ry="2"/><path d="M2.5 4v8c0 1.1 2.5 2 5.5 2s5.5-.9 5.5-2V4M2.5 8c0 1.1 2.5 2 5.5 2s5.5-.9 5.5-2"/>')
def settings():
  tabs=''.join(f'<div class="tab{" on" if n=="Team" else ""}">{i}{n}</div>' for n,i in [('General',GEN),('Library',LIB),('Team',TEAM),('Storage',STO)])
  def p(e,n,r,extra='',hv=False):return f'<div class="person{" hv" if hv else ""}"><div class="av">{e[0].upper()}</div><div class="who"><b>{e}</b><span>{n}</span></div>{extra}<span class="role">{r}</span></div>'
  rows=p('ada@studio.com','You','Owner')+p('bo@company.com','Joined Sep 12','Admin')+p('cy@company.com','Invited 2 hours ago','<span style="display:inline-flex;align-items:center;gap:6px">Member <span class="dot"></span> Pending</span>','<span class="q">Copy link</span><span class="q" style="margin-right:8px">Revoke</span>',True)
  return f'''<div class="stage"><div class="win"><div class="sb"><div class="tl"><i></i><i></i><i></i></div>{tabs}</div>
<div class="main"><h2>Team</h2><p class="desc">Manage who can access this library.</p>
<div class="sh"><h3>People</h3><span class="btn p">{PLUS}Invite</span></div>{rows}
<p class="foot">Invites expire after 24 hours. Pending people can't see the library until they accept.</p></div></div></div>'''
with sync_playwright() as pw:
  b=pw.chromium.launch()
  for mode,t in T.items():
    css=CSS
    for k,v in t.items():css=css.replace(f'VAR({k})',v)
    for name,fn in [('invite',invite),('settings',settings)]:
      body=fn()
      for k,v in t.items():body=body.replace(f'VAR({k})',v)
      pg=b.new_page(device_scale_factor=2,viewport={'width':1200,'height':800})
      pg.set_content(f'<style>{css}</style>{body}');pg.wait_for_timeout(200)
      pg.locator('.stage').screenshot(path=f'{name}-{mode}.png');pg.close()
  b.close()
