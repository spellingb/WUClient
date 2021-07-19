Function Get-Updates{
    [CmdletBinding()]
    Param(
    [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [Alias('Computername')]
    [string[]]$Computer = $env:COMPUTERNAME,

    [ValidateSet('Pending','Installed')]
    [switch]$UpdateType

        
    )

    Begin
    {
        $ErrorActionPreference = 'stop'

        Function Add-CustomMembers($object){

            $params = @(
                "KB",
                "Size",
                "IsDownloaded",
                "IsInstalled",
                "InstallDate",
                "Title"
                )
            $propertyset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$params)
            $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($propertyset)
            $object | Add-Member -NotePropertyName "KB" -NotePropertyValue $(if($update.KBArticleIDs -ne ""){"KB"+$update.KBArticleIDs}else{""})
            $object | Add-Member -NotePropertyName "Size" -NotePropertyValue "$([system.math]::Round($update.MaxDownloadSize/1MB, 0)) MB"
            $object | Add-Member -NotePropertyName "InstallDate" -NotePropertyValue $($update.LastDeploymentChangeTime.ToLocalTime())
            $object | Add-Member MemberSet PSStandardMembers $PSStandardMembers

        }
    }
    
    Process
    {
        foreach($server in $Computer)
        {
            Write-Verbose -Message ( "{0}: Starting Update Search." -f $server )
            try
            {
                $comtype = [type]::GetTypeFromProgID("Microsoft.Update.Session",$Computer, $true)
                $session = [activator]::CreateInstance($comtype)
                $searcher = $session.CreateUpdateSearcher()
                #$searcher = New-Object -ComObject 'Microsoft.Update.Searcher'
                $updates = $searcher.Search("IsInstalled = 0").updates
                Write-Verbose -Message ( "{0}: Found {1} updates. " -f $server,$updates.count)
            }
            Catch
            {
                Write-Warning ( "{0}: Unable to connect to windows Update Service" -f $Computer )
                Continue
            }

            if($updates.Count -eq 0)
            {
                Write-Warning ( "{0}: No Updates Pending" -f $server )
                continue
            } else {
                $updates | foreach{Add-CustomMembers -object $_}
            }
        }
    
    }
    
    End
    {
        
    }
}