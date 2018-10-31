<#
.Synopsis
   Configures WSUS on target computers
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
    [CmdletBinding(SupportsShouldProcess, 
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([String])]
    Param
    (
        # Name of computer to connect to. Can be a collection of computers.
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("Computer")] 
        [string[]]$ComputerName=$env:COMPUTERNAME,

        [string]$UpdateServer = "https://wsus.armor.com",

        [ValidateSet('Notify','DownloadOnly','DownloadAndInstall')]
        [string]$AUOption,

        [ValidateSet('EveryDay','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
        [string[]]$ScheduledInstallDay,

        [ValidateRange(0,23)]
        [Int32]$ScheduledInstallTime,

        [ValidateSet('Enable','Disable')]
        [string]$AllowAutomaticUpdates,
        
        [ValidateSet('Enable','Disable')]
        [string]$UseWSUSServer
        
          
    )

    Begin
    {
        Function Set-WUKey
        {
            [CmdletBinding()]
            Param(
                $RegKey,[ValidateSet('WU','AU')]$SubKey,
                $KeyName,
                $KeyValue,
                $Computer)
            $WUKey = Switch($Subkey)
            {
                "WU" {$regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate',$True)}
                "AU" {$regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate\AU',$True)}
            }
            try {
                Write-Verbose -Message ("{0}: Setting Key: {1} to value {2}" -f $Computer,$KeyName,$KeyValue)
                $WUKey.SetValue($KeyName,$KeyValue,[Microsoft.Win32.RegistryValueKind]::String)
                $WUKey.Close()
                Write-Host -ForegroundColor Green ( "{0}: Set Property {1} to value {2}" -f $Computer,$KeyName,$KeyValue )
                }
            catch {
                Write-Warning ("{0}: Unable to set Property {0} to value {1}" -f $Computer,$KeyName,$KeyValue)
            }
        }#Set-WUKey
    }
    Process
    {
        $ErrorActionPreference = 'stop'
        foreach($Computer in $ComputerName)
        {
            try
            {
                #Test connection to remote machine and get the 
                $remoteregistrystatus = (Get-Service -Name RemoteRegistry -ComputerName "$computer").status
                if($remoteregistrystatus -ne 'started')
                {
                    Set-Service -Name RemoteRegistry -ComputerName $computer -StartupType Manual -Status Running
                }
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
                $temp = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows',$True)

                If (-NOT ($temp.GetSubKeyNames() -contains 'WindowsUpdate')) 
                {
                    #Build the required registry keys
                    $temp.CreateSubKey('WindowsUpdate\AU') | Out-Null
                    $temp.Flush()
                }
                $temp.Close()
            }
            catch
            {
                Write-Warning ( "{0}: Unable to communicate to establish Remote Registy Connection." -f $Computer)
                $_
                break
            }

            #Set WU Update Server
            #$WSUSEnv = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate',$True)
            If ($PSBoundParameters['UpdateServer']) 
            {
                foreach($wukey in @('WUServer','WUStatusServer'))
                {
                    Set-WUKey -RegKey $reg -SubKey WU -KeyName $wukey -KeyValue $UpdateServer
                }
            }#UpdateServer

            #Set WSUS Client Configuration Options
            #$WSUSConfig = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate\AU',$True)

            If ($PSBoundParameters['AUOption']) 
            {
                $STRauoption = switch($auoption)
                {
                    'Notify'{2}
                    'DownloadOnly'{3}
                    'DownloadAndInstall'{4}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName AUOptions -KeyValue $STRauoption
            }#AUOption
            If ($PSBoundParameters['ScheduledInstallDay']) 
            {
                $STRInstallDay = switch($ScheduledInstallDay)
                {
                    'Everyday'{0}
                    'Sunday'{1}
                    'Monday'{2}
                    'Tuesday'{3}
                    'Wednesday'{4}
                    'Thursday'{5}
                    'Friday'{6}
                    'Saturday'{7}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName ScheduledInstallDay -KeyValue $STRInstallDay
            }#ScheduleInstallDay
            If ($PSBoundParameters['ScheduledInstallTime']) 
            {
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName ScheduledInstallTime -KeyValue $ScheduledInstallTime
            }#ScheduleInstallTime
            If ($PSBoundParameters['AllowAutomaticUpdates']) 
            {
                $strNoAutoUpdate = switch($AllowAutomaticUpdates)
                {
                    'Enable' {1}
                    'Disable' {0}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName NoAutoUpdate -KeyValue $strNoAutoUpdate
            }#AllowAutomaticUpdates
            If ($PSBoundParameters['UseWSUSServer']) 
            {
                $strUseWUServer = Switch($UseWSUSServer)
                {
                    'Enable' {1}
                    'Disable' {0}
                }
                Set-WUKey -RegKey $Reg -SubKey AU -KeyName UseWUServer -KeyValue $strUseWUServer
                Write-Verbose ("Setting Key: ")          
            }#UseWSUSServer
            
            #Restart WSUS Service and report in
            try {
                Get-Service -Name wuauserv -ComputerName $Computer -ErrorAction Stop | Restart-Service -Force -ErrorAction Stop
            }
            catch {
                Write-Verbose ""
                try {
                    $stopwu = '{0}\system32\cmd.exe /C sc \\{1} stop wuauserv' -f $env:windir,$Computer
                    $startwu = 'sc \\{0} start service' -f $Computer
                    Write-Verbose ( "{0}: Attempting to stop Windows Update Service with command: {1}" -f $Computer,$stopwu )
                    $stopwuresult = Invoke-Expression -Command $stopwu -ErrorAction Stop
                    if($stopwuresult -match "^Access.is.denied\.$"){
                        throw [System.Exception]::new(( "Access Denied to resource: WUAUSERV on Computer: {0}" -f $Compute ))
                        }
                    }
                catch [System.Exception] {
                    Write-Warning ( "Unable to Restart Windows Update (wuauserv) service on {0}." -f $Computer )
                    Write-Warning ( "Error is {0}" -f $_.Exception )
                }
                Catch {
                    Write-Warning ( "{0: Unhandled Exception}")
                    $_.Exception | ForEach-Object{Write-Warning $_ -ErrorAction SilentlyContinue}
                    $_.message | ForEach-Object{Write-Warning $_ -ErrorAction SilentlyContinue}
                }

                Write-Verbose ( "{0}: Attempting to start Windows Update Service with Command: {1}" -f $Computer,$startwu)
                
                Invoke-Expression -Command $startwu -ErrorAction Stop
                Write-Warning ( "Unable to Restart Windows Update (wuauserv) service on {0}." -f $Computer )
            }
            
            $Reg.Close()
        }#Foreach Computer

    }
    End
    {
    }
