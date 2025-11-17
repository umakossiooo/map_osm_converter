#!/usr/bin/env python3
"""
Unify road material colors in MTL file for better navigation clarity.
All navigable roads should have the same color so Ackermann robots can clearly see where to drive.
"""

import re
import sys
from pathlib import Path


def unify_road_colors(mtl_file: str, navigable_color: tuple = (0.15, 0.15, 0.15), non_navigable_color: tuple = (0.4, 0.4, 0.4)):
    """
    Unify road materials: navigable roads get one color (dark), non-navigable roads get another (lighter).
    This helps visually distinguish where Ackermann robots should navigate.
    
    Args:
        mtl_file: Path to MTL file
        navigable_color: RGB color tuple (0-1 range) for navigable roads (dark grey) - Ackermann vehicles
        non_navigable_color: RGB color tuple (0-1 range) for non-navigable roads (lighter grey) - narrow paths
    """
    mtl_path = Path(mtl_file)
    if not mtl_path.exists():
        print(f"❌ MTL file not found: {mtl_file}")
        return False
    
    # Read MTL file
    with open(mtl_path, 'r') as f:
        content = f.read()
    
    # IMPORTANT: OSM2World assigns ASPHALT to ALL roads (major and minor)
    # So we cannot reliably distinguish navigable vs non-navigable by material name alone.
    # The actual navigability is determined by the waypoint filtering (width/lanes/highway type).
    # 
    # For visualization:
    # - All ASPHALT/CONCRETE roads get dark grey (but not all are navigable - check *_navigable.json!)
    # - PAVING_STONE/PAVING/KERB get light grey (definitely non-navigable)
    # 
    # Use *_navigable.json files for actual navigability - visual colors are approximate!
    
    # Navigable road materials (suitable for Ackermann vehicles - major roads)
    # Note: These will be dark grey, but actual navigability is determined by waypoint filtering
    navigable_materials = [
        'ASPHALT', 'CONCRETE'  # Major roads, primary streets - Ackermann vehicles can navigate
    ]
    
    # Non-navigable road materials (too narrow, pedestrian areas, sidewalks)
    non_navigable_materials = [
        'PAVING_STONE', 'PAVING', 'KERB'  # Sidewalks, pedestrian areas, curbs - too narrow for Ackermann
    ]
    
    # Find all material definitions
    material_pattern = r'newmtl\s+(\w+)\s*\n(.*?)(?=\nnewmtl|\Z)'
    materials = re.findall(material_pattern, content, re.DOTALL)
    
    modified = False
    new_content = []
    i = 0
    
    # Process each material
    for match in re.finditer(material_pattern, content, re.DOTALL):
        material_name = match.group(1)
        material_block = match.group(0)
        
        # Check if this is a navigable road material
        is_navigable = any(nav_mat.lower() in material_name.lower() for nav_mat in navigable_materials)
        is_non_navigable = any(non_nav_mat.lower() in material_name.lower() for non_nav_mat in non_navigable_materials)
        
        if is_navigable:
            # Replace Kd (diffuse color) with navigable road color (dark grey)
            # Format: Kd r g b
            kd_pattern = r'(Kd\s+)[\d.]+(\s+)[\d.]+(\s+)[\d.]+'
            replacement = f'\\g<1>{navigable_color[0]}\\g<2>{navigable_color[1]}\\g<3>{navigable_color[2]}'
            
            if re.search(kd_pattern, material_block):
                material_block = re.sub(kd_pattern, replacement, material_block)
                modified = True
                print(f"  ✅ {material_name} → Navigable road color ({navigable_color[0]}, {navigable_color[1]}, {navigable_color[2]}) - Ackermann vehicles")
        
        elif is_non_navigable:
            # Replace Kd (diffuse color) with non-navigable road color (lighter grey)
            # Format: Kd r g b
            kd_pattern = r'(Kd\s+)[\d.]+(\s+)[\d.]+(\s+)[\d.]+'
            replacement = f'\\g<1>{non_navigable_color[0]}\\g<2>{non_navigable_color[1]}\\g<3>{non_navigable_color[2]}'
            
            if re.search(kd_pattern, material_block):
                material_block = re.sub(kd_pattern, replacement, material_block)
                modified = True
                print(f"  ⚠️  {material_name} → Non-navigable color ({non_navigable_color[0]}, {non_navigable_color[1]}, {non_navigable_color[2]}) - too narrow for Ackermann")
        
        new_content.append(material_block)
    
    if modified:
        # Write back
        with open(mtl_path, 'w') as f:
            f.write(''.join(new_content))
        print(f"✅ Unified road colors in {mtl_file}")
        return True
    else:
        print(f"⚠️  No road materials found to unify in {mtl_file}")
        return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 unify_road_colors.py <mtl_file> [nav_r] [nav_g] [nav_b] [non_nav_r] [non_nav_g] [non_nav_b]")
        print("Example: python3 unify_road_colors.py model.obj.mtl")
        print("  Default: navigable=(0.15,0.15,0.15 dark grey), non-navigable=(0.4,0.4,0.4 light grey)")
        sys.exit(1)
    
    mtl_file = sys.argv[1]
    
    # Optional color arguments
    if len(sys.argv) >= 8:
        nav_r, nav_g, nav_b = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
        non_nav_r, non_nav_g, non_nav_b = float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])
        navigable_color = (nav_r, nav_g, nav_b)
        non_navigable_color = (non_nav_r, non_nav_g, non_nav_b)
    else:
        navigable_color = (0.15, 0.15, 0.15)  # Dark grey - navigable roads (Ackermann vehicles)
        non_navigable_color = (0.4, 0.4, 0.4)  # Lighter grey - non-navigable paths (too narrow)
    
    unify_road_colors(mtl_file, navigable_color, non_navigable_color)

