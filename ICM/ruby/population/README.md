# Population Calculation in InfoWorks ICM with Census Data and Ruby

**Author:** Mohammad Reza Eslami  
**Wastewater Network Modeller | ICE Member (MICE) | Automation & Hydroinformatics Specialist**

**Date:** October 20, 2025

## Bringing GIS into Hydraulic Modeling Without External Libraries

In wastewater modeling, accurate subcatchment population estimates are essential for hydraulic simulations, regulatory compliance, and infrastructure planning. InfoWorks ICM provides tools to allocate census data, but these can be slow, manual, and inflexible—especially when handling varying occupancy factors or overlapping boundaries. To address these limitations, a fully automated, script-based solution was developed using pure Ruby inside ICM—bringing GIS capabilities directly into the platform.

### Why Not Use GIS Software?

GIS platforms like QGIS or ArcGIS are powerful, but they require exporting data, external processing, and re-importing results—introducing risk of errors and interruptions in workflow continuity. By embedding GIS logic directly within ICM, the process remains contained, reproducible, and fully automated. This approach uses the 1987 ray-casting algorithm by Franklin Antonio—a proven geoinformatics method—to perform point-in-polygon checks without external libraries.

### Overview of the Method

The script assigns populations to ICM subcatchments using census-based household points and occupancy factors. Key features include:

- Reads household CSV data (X, Y, occupancy factor).
- Accesses subcatchment polygon boundaries from ICM.
- Performs point-in-polygon checks using ray-casting.
- Sums occupants per subcatchment and updates ICM fields directly.
- Handles overlapping boundaries, missing data, and logs all diagnostics.

### Technical Architecture

The script uses pure Ruby within ICM to perform GIS-like spatial checks. The core is a 1987 ray-casting algorithm by Franklin Antonio, a simple yet powerful method to determine if a point (like a household location) lies inside a polygon (like a subcatchment). It works by drawing an imaginary line from the point in one direction and counting how many times it crosses the polygon’s edges. If the number of crossings is odd, the point is inside; if even, it’s outside. Here’s the function:

```ruby
# --- RAY-CASTING FUNCTION ---
def point_in_polygon(x, y, vertices)
  inside = false
  j = vertices.size - 1
  vertices.each_with_index do |(xi, yi), i|
    xj, yj = vertices[j]
    if ((yi > y) != (yj > y)) &&
       (x < (xj - xi) * (y - yi) / (yj - yi + 1e-10) + xi)
      inside = !inside
    end
    j = i
  end
  inside
end
```

### Data Preparation

Each census polygon contains attributes such as population and number of households.  
From these, an occupancy factor (e.g., persons per household) is calculated.  
Household point data is then intersected with census polygons so each point inherits an occupancy factor.  
These enriched household points are exported as a CSV and used within the Ruby script.

### CSV File Format

The script expects a CSV file containing household point data with the following columns:

- **WKT**: Geometry in Well-Known Text format. Can be `POINT (x y)` or `MULTIPOINT ((x y))`. The script handles both formats by extracting the coordinates.
- **oc** (or **OC**): Occupancy factor (persons per household), a numeric value greater than 0.

Additional columns like `objectid` and `waterconne` may be present but are ignored by the script.

**Example CSV Structure** (based on `only_HH.csv`):

```
WKT,objectid,waterconne,oc
"MULTIPOINT ((286205.09 649955.25))",46160,HH,2.630
"MULTIPOINT ((286243.12 649930.939999999))",46162,HH,2.630
...
```

The provided `only_HH.csv` file contains a sample of 4 household points with varying occupancy factors, demonstrating the expected format for use with the script.

### Prerequisites

- InfoWorks ICM software
- Ruby environment within ICM
- CSV file with household points in WKT format and occupancy factors

### How to Use

1. Open InfoWorks ICM and load your network.
2. Select the subcatchments you want to update (they must have valid polygon boundaries).
3. Run the `population.rb` script in ICM's Ruby console.
4. When prompted, select the CSV file containing the point data.
5. The script will process the points, assign populations, and update the subcatchments.
6. Review the output report for any issues (overlaps, unprocessed points, etc.).

### Example Use Case

A wastewater utility needs population estimates for 100 subcatchments. Census polygons are used to calculate occupancy factors (e.g., 2.3 urban, 2.8 rural) and assigned to household points. The script processes thousands of points, assigns them to subcatchments, flags overlaps, and updates population values in ICM.

### Sample Output

```
========================================
=== POPULATION ESTIMATION REPORT ===
========================================
SUBCATCHMENTS UPDATED: 100
  Subcatchment: SUB001, Estimated Population: 2456.78
  Subcatchment: SUB002, Estimated Population: 1890.32
POINTS IN OVERLAPPING SUBCATCHMENTS (4):
  Point: POINT (150.3 400.5), Subcatchments: [SUB005, SUB006]
UNPROCESSED POINTS (8):
  - 8 points: Not in any selected subcatchment
```

### Ray-Casting in Wastewater Modeling

Franklin Antonio's 1987 algorithm is versatile beyond population calculation:

- **Flood Risk Analysis:** Check if critical assets (e.g., pumping stations) lie within flood zones from ICM simulations.
- **Pollution Source Tracking:** Identify if spill points fall within subcatchments during water quality modeling.
- **Runoff Estimation:** Assign impervious surface points to subcatchments for stormwater calculations.
- **Compliance Checks:** Verify if infrastructure is within regulatory boundaries (e.g., treatment zones).

These tasks leverage ray-casting's efficiency for spatial queries, all in Ruby within ICM.

### Engineering Impact

- **Precision:** Uses exact polygon boundaries and household-level data.
- **Speed:** Processes thousands of points in minutes, no GUI needed.
- **Flexibility:** Adapts to different occupancy factors or datasets.
- **Innovation:** Revives a classic 1987 algorithm for modern automation.

This approach proves engineering's beauty: one challenge can be tackled with ICM's tools, GIS software, or this script—choose what fits your needs.

#InfoWorksICM #Ruby #WastewaterModelling #CensusData #RayCasting #HydraulicModelling