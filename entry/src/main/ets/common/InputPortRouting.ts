export enum InputSourceType {
  None = 0,
  Virtual = 1,
  Keyboard = 2,
  Mouse = 3,
  Gamepad = 4,
  BluetoothGamepad = 5,
  Unknown = 6
}

export interface InputDeviceInfo {
  deviceId: string;
  sourceType: InputSourceType;
  name: string;
}

export interface PortAssignState {
  portId: number;
  sourceType: InputSourceType;
  deviceId: string;
  isActive: boolean;
}

export interface InputSourceItem {
  label: string;
  type: InputSourceType;
  deviceId: string;
}

export function createDefaultPortAssignments(): PortAssignState[] {
  return [
    {
      portId: 0,
      sourceType: InputSourceType.Virtual,
      deviceId: '',
      isActive: true
    },
    {
      portId: 1,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    },
    {
      portId: 2,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    },
    {
      portId: 3,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    }
  ];
}

export function isVirtualSource(sourceType: InputSourceType): boolean {
  return sourceType === InputSourceType.Virtual;
}

export function buildInputSourceItems(devices: InputDeviceInfo[]): InputSourceItem[] {
  const items: InputSourceItem[] = [
    { label: '未分配', type: InputSourceType.None, deviceId: '' },
    { label: '虚拟手柄', type: InputSourceType.Virtual, deviceId: '' }
  ];

  devices.forEach((device: InputDeviceInfo) => {
    items.push({
      label: buildInputDeviceLabel(device),
      type: device.sourceType,
      deviceId: device.deviceId
    });
  });

  return items;
}

export function findPortAssignment(assignments: PortAssignState[], portId: number): PortAssignState {
  const found = assignments.find((item: PortAssignState) => item.portId === portId);
  if (found) {
    return found;
  }
  // Audit C-F6: log when portId not found to distinguish "port inactive" from "portId out of range"
  console.warn(`[InputPortRouting] findPortAssignment: portId=${portId} not in assignments (len=${assignments.length}), returning sentinel`);
  return {
    portId: portId,
    sourceType: InputSourceType.None,
    deviceId: '',
    isActive: false
  };
}

export function getInputSourceItemIndex(
  items: InputSourceItem[],
  sourceType: InputSourceType,
  deviceId: string
): number {
  const index = items.findIndex((item: InputSourceItem) => {
    if (item.type !== sourceType) {
      return false;
    }
    if (sourceType === InputSourceType.None || sourceType === InputSourceType.Virtual) {
      return true;
    }
    return item.deviceId === deviceId;
  });
  return index >= 0 ? index : 0;
}

export function updatePortAssignments(
  assignments: PortAssignState[],
  portId: number,
  sourceType: InputSourceType,
  deviceId: string
): PortAssignState[] {
  return assignments.map((item: PortAssignState) => {
    if (sourceType === InputSourceType.Virtual && item.sourceType === InputSourceType.Virtual &&
      item.portId !== portId) {
      return {
        portId: item.portId,
        sourceType: InputSourceType.None,
        deviceId: '',
        isActive: false
      };
    }
    if (item.portId !== portId) {
      return item;
    }
    return {
      portId: portId,
      sourceType: sourceType,
      deviceId: deviceId,
      isActive: sourceType !== InputSourceType.None
    };
  });
}

export function isVirtualPortActive(assignments: PortAssignState[], portId: number): boolean {
  return findPortAssignment(assignments, portId).sourceType === InputSourceType.Virtual;
}

function buildInputDeviceLabel(device: InputDeviceInfo): string {
  if (device.sourceType === InputSourceType.Keyboard) {
    return `键盘 ${device.name}`;
  }
  if (device.sourceType === InputSourceType.Mouse) {
    return `鼠标 ${device.name}`;
  }
  if (device.sourceType === InputSourceType.Gamepad) {
    return `手柄 ${device.name}`;
  }
  if (device.sourceType === InputSourceType.BluetoothGamepad) {
    return `蓝牙手柄 ${device.name}`;
  }
  return device.name;
}
