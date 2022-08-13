module network

struct Entry {
pub mut:
    score int
    ip string
}

struct AddressBook {
pub mut:
    entries shared []Entry
}

pub fn (mut ab AddressBook) add(ip string) {
    lock ab.entries {
        ab.entries << Entry{score: 0 ip: ip}
    }
}

pub fn (mut ab AddressBook) modify_trust(ip string, diff int) {
    lock ab.entries {
        for i in 0..ab.entries.len {
            if ab.entries[i].ip == ip {
                ab.entries[i].score += diff
            }
        }
        ab.entries.sort(a.score > b.score)
    }
}
