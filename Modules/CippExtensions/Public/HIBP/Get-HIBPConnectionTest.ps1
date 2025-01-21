function Get-HIBPConnectionTest {
    $uri = 'https://haveibeenpwned.com/api/v3/subscription/status'
    try {
        Invoke-RestMethod -Uri $uri -Headers (Get-HIBPAuth)
    } catch {
        throw "Failed to connect to HIBP: $($_.Exception.Message)"
    }
}
