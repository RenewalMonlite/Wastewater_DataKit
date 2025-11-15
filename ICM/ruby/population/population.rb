#### Work only for selected polygones


begin
  # --- RAY-CASTING FUNCTION ---
  def point_in_polygon(x, y, vertices)
    # vertices is an array of [x, y] pairs (e.g., [[x1, y1], [x2, y2], ...])
    inside = false
    j = vertices.size - 1

    vertices.each_with_index do |(xi, yi), i|
      xj, yj = vertices[j]
      # Check if the ray from (x, y) to the right intersects the edge from (xi, yi) to (xj, yj)
      if ((yi > y) != (yj > y)) &&
         (x < (xj - xi) * (y - yi) / (yj - yi + 1e-10) + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end

  # --- INITIALIZATION ---
  net = WSApplication.current_network
  raise "Error: Current network not found" unless net

  # Get selected subcatchments
  selected_subcatchments = net.row_objects('hw_subcatchment').select(&:selected?)
  raise "Error: No subcatchments selected in InfoWorks ICM" if selected_subcatchments.empty?
  puts "Found #{selected_subcatchments.size} selected subcatchments."

  # --- CONFIGURATION ---
  puts "\nOpening file dialog to select point layer CSV file..."
  point_csv = WSApplication.file_dialog(false, 'csv', 'CSV Files', 'Select Point Layer CSV', 'C:/Wastewater_DataKit/ICM/ruby/population', false).to_s.strip
  raise "Error: No file selected" if point_csv.empty?
  puts "Selected point layer CSV: #{point_csv}"

  # --- DATA STORAGE ---
  unprocessed_points = []
  processed_subcatchments = []
  error_log = []
  invalid_geometry_subcatchments = []
  overlapping_subcatchment_points = []

  # --- STEP 1: READ POINT LAYER CSV ---
  puts "\n--- Reading Point Layer Data ---"
  require 'csv'
  raise "Error: Point CSV file not found at '#{point_csv}'" unless File.exist?(point_csv)

  # Expected CSV format:
  # - WKT column: Geometry in WKT format (POINT or MULTIPOINT)
  # - oc column: Occupancy factor (persons per household)
  # Additional columns (e.g., objectid, waterconne) are ignored
  points = []
  begin
    point_data = CSV.read(point_csv, headers: true, skip_blanks: true)
    raise "Error: Point CSV is empty or invalid" if point_data.empty?

    puts "Point CSV Headers: #{point_data.headers.join(', ')}"
    puts "First point row: #{point_data.first.to_h}"

    point_data.each_with_index do |row, i|
      begin
        wkt = row['WKT'] || row['wkt'] || row['geometry']
        population = (row['oc'] || row['OC'] || 0).to_f
        raise "Missing WKT geometry for row #{i + 2}" if wkt.nil? || wkt.empty?
        raise "Missing or invalid 'oc' population for row #{i + 2}" if population <= 0

        # Handle MULTIPOINT by extracting first POINT
        if wkt.start_with?('MULTIPOINT')
          coords = wkt.match(/MULTIPOINT\s*\(\(?\s*([\d\.\-\s]+)\s*\)?\)/m)&.captures&.first
          raise "Invalid MULTIPOINT format for row #{i + 2}: #{wkt}" unless coords
          wkt = "POINT (#{coords.strip})"
        end
        coords = wkt.match(/POINT\s*\(\s*([\d\.\-]+)\s+([\d\.\-]+)\s*\)/)&.captures&.map(&:to_f)
        raise "Invalid POINT coordinates for row #{i + 2}: #{wkt}" unless coords
        points << { wkt: wkt, x: coords[0], y: coords[1], population: population }
      rescue => e
        error_log << { file: 'Point CSV', row: i + 2, data: row.to_h, error: "Row processing error: #{e.message}" }
      end
    end
    puts "Successfully loaded #{points.size} points with population data."
  rescue => e
    raise "Fatal Error reading point CSV '#{point_csv}': #{e.message}"
  end

  # --- STEP 2: PROCESS GEOMETRIES AND CALCULATE POPULATION ---
  puts "\n--- Processing Geometries and Calculating Population ---"
  net.transaction_begin

  # Get subcatchment geometries
  subcatchment_data = {}
  selected_subcatchments.each do |sub|
    sub_id = sub.subcatchment_id
    begin
      boundary_array = sub.boundary_array
      if boundary_array && boundary_array.is_a?(Array) && boundary_array.size >= 6
        vertices = boundary_array.each_slice(2).to_a
        subcatchment_data[sub_id] = {
          sub: sub,
          vertices: vertices
        }
      else
        invalid_geometry_subcatchments << { sub_id: sub_id, reason: "Invalid or empty boundary_array: #{boundary_array.inspect}" }
      end
    rescue => e
      invalid_geometry_subcatchments << { sub_id: sub_id, reason: "Error processing geometry: #{e.message}" }
    end
  end
  puts "Processed geometries for #{subcatchment_data.size} / #{selected_subcatchments.size} selected subcatchments."

  # Initialize population hash
  subcatchment_populations = Hash.new(0.0)

  # Main Processing Loop
  total_points = points.size
  assigned_points = 0

  points.each_with_index do |point_data, i|
    begin
      point_x, point_y, population = point_data[:x], point_data[:y], point_data[:population]
      point_wkt = point_data[:wkt]

      # Find containing subcatchment (ray-casting)
      sub_matches = []
      subcatchment_data.each do |sub_id, sub_data|
        begin
          if point_in_polygon(point_x, point_y, sub_data[:vertices])
            sub_matches << sub_id
          end
        rescue => e
          error_log << { point_wkt: point_wkt, error: "Subcatchment ray-casting test error (sub_id: #{sub_id}): #{e.message}" }
        end
      end

      if sub_matches.size > 1
        overlapping_subcatchment_points << {
          point_wkt: point_wkt,
          subcatchments: sub_matches
        }
        # Assign population to all matching subcatchments
        sub_matches.each do |sub_id|
          subcatchment_populations[sub_id] += population
        end
        assigned_points += 1
      elsif sub_matches.size == 1
        subcatchment_populations[sub_matches.first] += population
        assigned_points += 1
      else
        unprocessed_points << {
          point_wkt: point_wkt,
          reason: "Not in any selected subcatchment",
          closest_sub: subcatchment_data.map { |id, data|
            dist = Math.sqrt((point_x - data[:vertices][0][0])**2 + (point_y - data[:vertices][0][1])**2)
            [id, dist]
          }.min_by { |_, dist| dist }
        }
      end

      # Progress reporting
      if (i + 1) % 1000 == 0 || (i + 1) == total_points
       # puts "Processed #{i + 1} / #{total_points} points (#{( (i + 1).to_f / total_points * 100).round(1)}%). Assigned: #{assigned_points}."
      end
    rescue => e
      error_log << { point_wkt: point_wkt, error: "Processing error: #{e.message}" }
    end
  end

  # --- STEP 3: UPDATE ICM NETWORK ---
  puts "\n--- Updating Network ---"
  selected_subcatchments.each do |sub|
    sub_id = sub.subcatchment_id
    if subcatchment_populations.key?(sub_id)
      population = subcatchment_populations[sub_id].round(2)
      sub.Population = population
      sub.write
      processed_subcatchments << { sub_id: sub_id, population: population }
    end
  end

  # Save overlapping subcatchment IDs to CSV
  require 'fileutils'
#  require 'csv'
  output_dir = File.dirname(point_csv)
  output_file = File.join(output_dir, 'overlapping_subcatchments.txt')
  begin
    # Collect unique subcatchment IDs from overlapping points
    overlapping_sub_ids = overlapping_subcatchment_points.flat_map { |overlap| overlap[:subcatchments] }.uniq
    CSV.open(output_file, 'w') do |csv|
      csv << ['Subcatchment_ID']
      overlapping_sub_ids.each do |sub_id|
        csv << [sub_id]
      end
    end
    puts "Overlapping subcatchments report saved to: #{output_file}"
  rescue => e
    puts "Error saving overlapping subcatchments CSV: #{e.message}"
  end

  net.transaction_commit
  puts "Population updates have been committed to the network."

rescue => e
  net.transaction_rollback if net
  puts "\nFATAL ERROR during processing: #{e.message}"
  puts e.backtrace.join("\n")
  raise
ensure
  # --- STEP 4: FINAL REPORT ---
  puts "\n\n========================================"
  puts "=== POPULATION ESTIMATION REPORT ==="
  puts "========================================"

  puts "\nSUBCATCHMENTS UPDATED: #{processed_subcatchments.size}"
  if processed_subcatchments.empty?
    puts "No subcatchments were updated."
  else
    processed_subcatchments.each do |sub|
      puts "  Subcatchment: #{sub[:sub_id]}, Estimated Population: #{sub[:population]}"
    end
  end

  unless invalid_geometry_subcatchments.empty?
    puts "\nSUBCATCHMENTS WITH INVALID GEOMETRY (#{invalid_geometry_subcatchments.size}):"
    invalid_geometry_subcatchments.each do |sub|
      puts "  Subcatchment: #{sub[:sub_id]}, Reason: #{sub[:reason]}"
    end
  end

  unless unprocessed_points.empty?
    puts "\nUNPROCESSED POINTS (#{unprocessed_points.size}):"
    unprocessed_points.group_by { |p| p[:reason] }.each do |reason, points|
      puts "  - #{points.size} points: #{reason}"
      points.each do |point|
        if point[:closest_sub]
          sub_id, dist = point[:closest_sub]
       #   puts "    Point: #{point[:point_wkt]}, Closest Subcatchment: #{sub_id}, Distance: #{dist.round(2)}m"
        end
      end
    end
  end

  unless overlapping_subcatchment_points.empty?
    puts "\nPOINTS IN OVERLAPPING SUBCATCHMENTS (#{overlapping_subcatchment_points.size}):"
    overlapping_subcatchment_points.each do |overlap|
      puts "  Point: #{overlap[:point_wkt]}, Subcatchments: [#{overlap[:subcatchments].join(', ')}]"
    end
  end

  unless error_log.empty?
    puts "\nERRORS ENCOUNTERED DURING PROCESSING (#{error_log.size}):"
    error_log.each do |err|
      puts "  Point: #{err[:point_wkt] || 'N/A'}, Error: #{err[:error]}"
    end
  end

  puts "\n\n=== INSTRUCTIONS ==="
  puts "1. This script uses a ray-casting algorithm to check if points lie within actual subcatchment boundaries."
  puts "2. Points in overlapping subcatchments are assigned to all matching subcatchments."
  puts "3. Check 'POINTS IN OVERLAPPING SUBCATCHMENTS' section to identify points assigned to multiple subcatchments."
  puts "4. Verify unprocessed points for closest subcatchment to diagnose coordinate issues."
  puts "5. Check subcatchment boundaries in GeoPlan or QGIS (EPSG:27700)."
  puts "6. Review the updated Population field in GeoPlan or grid view."
  puts "\n--- SCRIPT FINISHED ---"
end

