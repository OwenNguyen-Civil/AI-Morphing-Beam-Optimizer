function Cost = ObjectiveFunction_GA_Morph(x, Input_P)
    Cost = 1e12; 
    

    if x(5) < 25, x(5) = 0; end
    
    PolyCoords = generate_morph_section(x);
    if isempty(PolyCoords), return; end
    
    try
    
        Load.Mx = Input_P.M_Nmm; Load.My = Input_P.My_Nmm; Load.Nz = 0;
        [~, Geom] = calc_normal_stress(PolyCoords, [], Load);
        [~, Shear] = calc_shear_stress(PolyCoords, Input_P.V_N, Geom); 
        [VM_Max, ~, ~] = calc_von_mises(Geom, Load, Shear, Input_P.Fy);
        
   
        Area_Abs = abs(Geom.Area);
        I_min = min(Geom.Ix, Geom.Iy);
        Lambda = Input_P.L_mm / sqrt(I_min/Area_Abs);
        Delta = (5 * Input_P.M_Nmm * Input_P.L_mm^2) / (48 * Input_P.E * Geom.Ix);
        
  
        Base_Cost = (Area_Abs * 1e-6) * (Input_P.L_mm * 1e-3) * 7850;
        
    
        P_Stress = 0; P_Buckling = 0; P_Deflection = 0; P_Gap = 0; P_Torsion = 0;
        Weight = 1e7;
        
        if VM_Max > Input_P.Fy, P_Stress = (VM_Max/Input_P.Fy - 1) * Weight; end
        if Lambda > 150, P_Buckling = (Lambda/150 - 1) * Weight; end
        if Delta > Input_P.L_mm/250, P_Deflection = (Delta/(Input_P.L_mm/250) - 1) * Weight; end
        
        Gap = x(5)*2;
        if Gap > 1 && Gap < 150, P_Gap = 1e9; end % Vùng tử thần
        if Gap > 0, P_Gap = P_Gap + Gap*50; end % Tiền hàn (nhẹ)
        


        if Input_P.My_Nmm > 500e6 % Ngưỡng Xoắn lớn (500 kNm)
            if Gap < 150 
                P_Torsion = 1e11; % Phạt cực nặng để ép nó tách bụng ra
            end
        end
        % ==============================================
        
        Cost = Base_Cost + P_Stress + P_Buckling + P_Deflection + P_Gap + P_Torsion;
        
    catch
        Cost = 1e12;
    end

end
