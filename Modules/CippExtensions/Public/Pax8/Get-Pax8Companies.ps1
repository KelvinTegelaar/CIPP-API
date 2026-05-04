function Get-Pax8Companies {
    $Companies = Get-Pax8PagedData -Path 'companies' -Query @{ status = 'Active' }
    return @($Companies | Where-Object { $_.status -eq 'Active' -or [string]::IsNullOrWhiteSpace($_.status) })
}
