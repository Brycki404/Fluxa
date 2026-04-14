local QueueItem = {}
QueueItem.__index = QueueItem

export type QueueItem = {
	Priority: number;
	Value: any;
	GetPriority: (QueueItem)->number;
	GetValue: (QueueItem)->any;
	SetPriority: (QueueItem, number)->();
	SetValue: (QueueItem, any)->();
	Destroy: (QueueItem)->();
}

function QueueItem.new(priority:number, value:any)
	local queueitem = {Priority = priority, Value = value}
	return setmetatable(queueitem, QueueItem)
end

function QueueItem:GetPriority(): number
	return self.Priority
end

function QueueItem:GetValue(): any
	return self.Value
end

function QueueItem:SetPriority(priority:number): ()
	self.Priority = priority
end

function QueueItem:SetValue(value:any): ()
	self.Value = value
end

function QueueItem:Destroy(): ()
	if self.Value:IsA("Instance") then
		self.Value:Destroy()
	elseif self.Value:IsA("RBXScriptConnection") then
		if self.Value.Connected then
			self.Value:Disconnect()
		end
	end
	self.Value = nil
end

return QueueItem