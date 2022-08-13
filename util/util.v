module util

// Returns the string or a hexlified version depending on
// whether all characters are printable or not.
pub fn sanitize_binary(data string) string {
    mut safe := true
    for c in data {
        // TODO: punctuation
        if !c.is_alnum() {
            safe = false
            break
        }
    }
    if !safe {
        return data.bytes().hex()
    }
    return data
}
