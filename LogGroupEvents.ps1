Import-Module -Name 'ActiveDirectory'

. "$PSScriptRoot\Config.ps1"

$domainControllers = Get-ADDomainController -Filter * | Foreach-Object -MemberName HostName

$con = New-Object -TypeName 'System.Data.SqlClient.SqlConnection'
$con.ConnectionString = $Script:Config.ConnectionString
$con.Open()

foreach ($dc in $domainControllers)
{
    $cmd = New-Object -TypeName 'System.Data.SqlClient.SqlCommand'
    $cmd.Connection = $con
    $cmd.CommandType = 'Text'
    $cmd.CommandText = "SELECT MAX(timeCreated) AS [Time] FROM dbo.GroupEvent WHERE domainController='$dc'"
    $rst = $cmd.ExecuteReader([System.Data.CommandBehavior]::SingleRow)
    if (-not $rst.Read())
    {
        Write-Error 'Failed to read max time from database'
        exit
    }
    $maxTime = $rst['Time']
    $rst.Dispose()
    $cmd.Dispose()
    if ($maxTime -is [System.DBNull])
    {
        $maxTime = [DateTime]::MinValue
    }
    try
    {
        $events = Get-WinEvent -ComputerName $dc -FilterHashTable @{LogName='Security';StartTime=$maxTime;ID=4732,4733,4728,4729,4756,4757} -ErrorAction Stop
    }
    catch
    {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*')
        {
            continue
        }
        throw
    }
    foreach ($event in $events)
    {
        $xml = [xml]$event.ToXml()
        $groupName = ''
        $groupSid = ''
        $memberName = ''
        $memberSid = ''
        $userName = ''
        $userSid = ''
        foreach ($node in $xml.Event.EventData.ChildNodes)
        {
            switch ($node.Name)
            {
                'MemberSid' {$memberSid = $node.'#text'}
                'TargetUserName' {$groupName = $node.'#text'}
                'TargetSid' {$groupSid = $node.'#text'}
                'SubjectUserName' {$userName = $node.'#text'}
                'SubjectUserSid' {$userSid = $node.'#text'}
            }
        }
        if ($groupName -notlike 'GA-*')
        {
            if ($memberSid.Length -gt 0)
            {
                $memberName = (Get-ADObject -Filter {objectSID -eq $memberSid} -Properties sAMAccountName).sAMAccountName
            }
            $cmd = New-Object -TypeName 'System.Data.SqlClient.SqlCommand'
            $cmd.Connection = $con
            $cmd.CommandType = 'Text'
            $cmd.CommandText = 'EXECUTE dbo.spInsertNewGroupEvent @idString,@timeCreated,@domainController,@eventId,@groupName,@groupSid,@memberName,@memberSid,@userName,@userSid'
            [void]$cmd.Parameters.AddWithValue('idString', $event.MachineName + $event.TimeCreated.ToFileTimeUtc() + 'Security' + $event.RecordId)
            [void]$cmd.Parameters.AddWithValue('timeCreated', $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.fff'))
            [void]$cmd.Parameters.AddWithValue('domainController', $dc)
            [void]$cmd.Parameters.AddWithValue('eventId', $event.Id)
            [void]$cmd.Parameters.AddWithValue('groupName', $groupName)
            [void]$cmd.Parameters.AddWithValue('groupSid', $groupSid)
            [void]$cmd.Parameters.AddWithValue('memberName', $memberName)
            [void]$cmd.Parameters.AddWithValue('memberSid',$memberSid)
            [void]$cmd.Parameters.AddWithValue('userName', $userName)
            [void]$cmd.Parameters.AddWithValue('userSid', $userSid)
            [void]$cmd.ExecuteNonQuery()
            $cmd.Dispose()
        }
    }
}
