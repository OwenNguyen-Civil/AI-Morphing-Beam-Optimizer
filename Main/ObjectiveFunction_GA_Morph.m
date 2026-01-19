function Cost = ObjectiveFunction_GA_Morph(x, Input_P)
    Cost = 1e12; 
    
    % 1. MAGNET EFFECT (Snap to I-Beam for light loads - Legacy Logic)
    if x(5) < 25, x(5) = 0; end
    
    PolyCoords = generate_morph_section(x);
    if isempty(PolyCoords), return; end
    
    try
        % 2. BASIC CALCULATIONS
        Load.Mx = Input_P.M_Nmm; Load.My = Input_P.My_Nmm; Load.Nz = 0;
        [~, Geom] = calc_normal_stress(PolyCoords, [], Load);
        [~, Shear] = calc_shear_stress(PolyCoords, Input_P.V_N, Geom); 
        [VM_Max, ~, ~] = calc_von_mises(Geom, Load, Shear, Input_P.Fy);
        
        % Global Stability & Deflection
        Area_Abs = abs(Geom.Area);
        I_min = min(Geom.Ix, Geom.Iy);
        Lambda = Input_P.L_mm / sqrt(I_min/Area_Abs);
        Delta = (5 * Input_P.M_Nmm * Input_P.L_mm^2) / (48 * Input_P.E * Geom.Ix);
        
        % 3. OBJECTIVE FUNCTION (Material Saving)
        Base_Cost = (Area_Abs * 1e-6) * (Input_P.L_mm * 1e-3) * 7850;
        
        % 4. PENALTY FUNCTIONS
        Weight = 1e7;
        
        % --- Basic Penalties (Strength, Deflection, Slenderness) ---
        P_Stress = 0; if VM_Max > Input_P.Fy, P_Stress = (VM_Max/Input_P.Fy - 1) * Weight; end
        P_Buckling = 0; if Lambda > 150, P_Buckling = (Lambda/150 - 1) * Weight; end
        P_Deflection = 0; if Delta > Input_P.L_mm/250, P_Deflection = (Delta/(Input_P.L_mm/250) - 1) * Weight; end
        
        % --- Topology Penalties (Dead Zone & Welding Cost) ---
        P_Gap = 0; Gap = x(5)*2;
        if Gap > 1 && Gap < 150, P_Gap = 1e9; end 
        if Gap > 0, P_Gap = P_Gap + Gap*50; end 
        
        % --- Torsion Penalty (Old Logic - Kept As Is) ---
        P_Torsion = 0;
        if Input_P.My_Nmm > 500e6 
            if Gap < 150, P_Torsion = 1e11; end
        end
        
        % ==================================================================
        % [NEW] SHEAR SAFETY LOGIC (THE "SAFETY LOCK" UPDATE)
        % ==================================================================
        
        P_ShearStability = 0;
        P_WebSlenderness = 0;
        
        % A. FORCE BOX SECTION FOR HIGH SHEAR
        % If shear force > 1000 kN (100 Tons), I-Beam poses high risk for local stability.
        % Mandatory web separation (Gap > 150) to form a box/composite girder.
        if Input_P.V_N > 1000e3 
             if Gap < 150
                 P_ShearStability = 1e11; % Severe penalty (Equivalent to torsion penalty)
             end
        end
        
        % B. WEB SLENDERNESS CONTROL (h/tw)
        % Prevent "Paper Web" scenario (e.g., 1m height with 20mm thickness).
        % Per standards, h/tw should not be excessive without stiffeners.
        h_approx = x(1); % Beam height
        tw = x(4);       % Web thickness
        Ratio_h_tw = h_approx / tw;
        
        Limit_h_tw = 60; % Safety limit (Empirical for unstiffened beams)
        
        if Ratio_h_tw > Limit_h_tw
            % Exponential penalty to force immediate increase in tw or decrease in h
            P_WebSlenderness = ((Ratio_h_tw / Limit_h_tw)^2) * Weight; 
        end
        % ==================================================================
        
        Cost = Base_Cost + P_Stress + P_Buckling + P_Deflection + P_Gap + ...
               P_Torsion + P_ShearStability + P_WebSlenderness;
        
    catch
        Cost = 1e12;
    end
end
