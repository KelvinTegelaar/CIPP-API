function Remove-EmptyArrays ($Object) {
    if ($Object -is [Array]) {
        foreach ($Item in $Object) { Remove-EmptyArrays $Item }
    } elseif ($Object -is [HashTable]) {
        foreach ($Key in @($Object.get_Keys())) {
            if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
                $Object.Remove($Key)
            } else { Remove-EmptyArrays $Object[$Key] }
        }
    } elseif ($Object -is [PSCustomObject]) {
        foreach ($Name in @($Object.PSObject.Properties.Name)) {
            if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
                $Object.PSObject.Properties.Remove($Name)
            } elseif ($null -eq $Object.$Name) {
                $Object.PSObject.Properties.Remove($Name)
            } else { Remove-EmptyArrays $Object.$Name }
        }
    }
}
