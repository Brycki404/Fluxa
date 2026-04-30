# Pose

Represents a joint transform dictionary and provides pose math utilities.

## Key Features
- Create, clone, and interpolate poses
- Additive blending and masking

## API
- `Pose.new(data?)`
- `Pose:Clone()`
- `Pose:Lerp(other, alpha)`
- `Pose:Additive(addPose, weight)`
- `Pose:ApplyMask(mask)`

See source for details and usage.