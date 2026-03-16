# Lessons — What I Learned & What Broke

---

## The SSH rabbit hole

I spent way more time trying to SSH into the VM from my Mac than I did actually configuring the firewall. The Mac's VMware kernel extensions never loaded properly. NAT networking just silently didn't work, no clear error, no obvious fix. I went through bridged mode, NAT mode, tried restarting VMware services, checked Security settings, all of it.

Eventually I stepped back and asked a simple question: do I actually need SSH for this? The answer was no. The VMware console window is a terminal. Nothing in this lab requires SSH.

Switching to a dual-VM setup with Ubuntu as the target, Kali as the scanner, both on a Host-Only network inside VMware. This completely bypassed the Mac networking issue and honestly made the lab better. Having a real attacker machine scanning a real target is more interesting than running nmap from your own laptop against a VM on the same machine.

---

## The rule that has to come first

Before I understood what DROP policy actually meant, I was treating it like a setting you turn on at the end. It's not. The moment you run `iptables -P INPUT DROP`, every packet that doesn't match an existing rule gets silently discarded — including SSH connections, including your own traffic. There's no grace period.

The correct order is:
1. Add every ACCEPT rule you need
2. Set DROP policy last

I got lucky working from the console since I couldn't lock myself out the traditional way , but if I'd been SSHed in and set DROP before adding the SSH rule, that session would have died instantly and I'd have had to restore a snapshot. It's the kind of mistake you only need to make once.

---

## Things that actually clicked

**iptables and ufw aren't two different firewalls.**

I knew this intellectually before starting but it didn't really land until I ran `sudo ufw show raw` and saw the iptables chains ufw had generated. They looked almost identical to what I'd written manually in Path A. ufw is just a friendlier way to write the same rules — the kernel is doing the same thing underneath either way.

**Why ESTABLISHED,RELATED actually matters.**

This one confused me at first. If I allow outbound DNS on port 53, why do I also need to allow the reply inbound? The answer is that each packet hits the INPUT chain fresh — the firewall doesn't automatically know a reply belongs to something you already approved unless you tell it to track connections. The ESTABLISHED,RELATED rule is what makes it stateful. Without it the server asks a question and the answer gets dropped on the way back in.

**--dport and --sport aren't interchangeable.**

dport is the destination port, the port being knocked on. sport is the source port, the port the sender's packet came from. When Kali connects to Ubuntu's SSH, it's hitting port 22 on Ubuntu, so the INPUT rule uses `--dport 22`. When Ubuntu replies, the reply leaves from port 22, so the OUTPUT rule uses `--sport 22`. Getting these mixed up causes a subtle failure mode where traffic looks like it should be working but replies never make it back. Nothing errors out — it just silently doesn't work.

**DROP and REJECT feel different from the attacker's side.**

Testing with netcat from Kali made this concrete in a way that reading about it didn't. A DROPped port just hangs until timeout — five seconds of nothing. A REJECTed port comes back immediately with "Connection refused." If you're scanning a server and a port times out, you know there's a firewall. If it refuses immediately, the port is closed but the host responded. DROP is stealthier. REJECT is more honest. Which one you want depends on the situation.

**Rate limiting logs isn't optional.**

During the nmap scans, the logs were getting hammered with multiple entries per second per port nmap tried. Against an internet-facing server with real scanners hitting it constantly, that would fill disk and make the logs useless for finding anything real. The `--limit 5/min` flag on LOG rules isn't just a nice-to-have, it's what makes logging actually useful.

---

## Things that broke

**apt stopped working after I set OUTPUT to DROP.**

I added HTTP and HTTPS outbound rules but forgot DNS. apt tried to resolve `archive.ubuntu.com`, got no response, and timed out. The error message said "Temporary failure resolving" which was a clear hint once I knew what to look for. Added outbound port 53 rules and it worked immediately. DNS is one of those things that's completely invisible when it works and breaks everything when it doesn't.

**nmap showed port 80 as `closed`, not `open`.**

My iptables rule was correct. The firewall was letting port 80 through. But `closed` in nmap means the firewall allowed it and the OS sent back a TCP RST because nothing was listening. There was no web server running. Once I installed nginx and started it, port 80 showed `open`. This distinction matters:

- `open` → firewall allowed it, service accepted it
- `closed` → firewall allowed it, nothing listening
- `filtered` → firewall dropped it, no response

`closed` isn't a firewall problem. It just means the port is available but unused.

**ufw show raw looked nothing like what I expected.**

After enabling ufw I ran `sudo ufw show raw` expecting to see my five simple allow rules. Instead there were chains called `ufw-before-input`, `ufw-user-input`, `ufw-after-input` and several others. It took a minute to understand that ufw builds a layered chain structure. Previous-rules handle loopback and connection tracking automatically, user-rules contain your custom allow rules, after-rules handle logging and final cleanup. Once I understood the flow it made sense, but the first look at it was genuinely confusing.

**MicroK8s in the logs.**

The ufw logs were full of blocks going to `10.1.220.207` via a `cali*` interface, not from Kali, but from the Ubuntu VM itself. Turns out MicroK8s (Kubernetes) was installed on the Ubuntu VM and was constantly trying to talk to its own internal pods. The deny outgoing policy was blocking all of it. It's harmless for the lab but it's a good real-world example of what deny-by-default actually means. It doesn't just block attackers, it blocks everything including legitimate internal traffic you didn't plan for. You have to explicitly allow what you want to keep.

---

## What I'd do differently

Install nginx before testing the HTTP/HTTPS rules. Seeing `closed` on port 80 when you just wrote an ACCEPT rule for it is confusing until you understand the open/closed/filtered distinction. Having a service actually running makes the test results cleaner.

Keep the log watch open in a second terminal the whole time. Running `sudo tail -f /var/log/ufw.log` while nmap scans from Kali makes the firewall behavior visible in real time — you can watch the blocks appear as each port gets hit. It turns abstract rules into something concrete.

---

## Quick reference — nmap results

| Result | What it means | Firewall state |
|---|---|---|
| `open` | Service accepted the connection | ACCEPT rule matched, service running |
| `closed` | OS refused — nothing listening | ACCEPT rule matched, no service |
| `filtered` | No response at all | DROP rule or default DROP matched |
| `open\|filtered` | Can't tell (common with UDP) | Ambiguous — try a TCP scan |