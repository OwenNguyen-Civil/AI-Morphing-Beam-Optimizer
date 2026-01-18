%% --- MAIN SCRIPT: MORPHING BEAM OPTIMIZER (FINAL PERFECT) ---
clc; clear; close all;

%% 1. SELECT SCENARIO
% 1 = Economy I-Beam
% 2 = Constrained H-Beam
% 3 = Arup Box Girder
% 4 = Double-Web Transfer Beam
CurrentCase = 4;  % <--- CHANGE THIS NUMBER TO RUN OTHER CASES
fprintf('>>> STARTING SCENARIO NUMBER: %d...\n', CurrentCase);

%% 2. SET PARAMETERS & VARIABLES
Input.Fy = 355;      % MPa
Input.E  = 2.1e5;    % MPa

% Declare variables (IMPORTANT: DO NOT DELETE THIS LINE)
nvars = 5; % [h, b, tf, tw, sep]

% Default variable bounds
lb = [400,  200, 10,  8,   0]; 
ub = [1200, 800, 50, 30, 400]; 

switch CurrentCase
    case 1 % ECONOMY I-BEAM
        CaseName = 'ECONOMY I-BEAM';
        Input.L_m = 12;
        Input.M_kNm = 800;   
        Input.My_kNm = 0;   % Lateral load = 0 to yield an I-Beam
        Input.V_kN = 0;     % Shear = 0
        ub(1) = 1200; 
        
    case 2 % CONSTRAINED H-BEAM
        CaseName = 'CONSTRAINED H-BEAM';
        Input.L_m = 9;
        Input.M_kNm = 1500; Input.My_kNm = 100; Input.V_kN = 400;
        ub(1) = 500;  % Height constrained
        ub(2) = 1000;
        
    case 3 % ARUP BOX GIRDER
        CaseName = 'ARUP BOX GIRDER';
        Input.L_m = 15;
        Input.M_kNm = 2500; Input.My_kNm = 1500; Input.V_kN = 500;
        ub(1) = 1200; ub(5) = 600;
        
    case 4 % DOUBLE-WEB BEAST
        CaseName = 'DOUBLE-WEB TRANSFER BEAM';
        Input.L_m = 6;
        Input.M_kNm = 350; Input.My_kNm = 400; Input.V_kN = 3500;
        ub(1) = 850; ub(4) = 25;
end

% Unit Conversion
Input.L_mm = Input.L_m*1000;
Input.M_Nmm = Input.M_kNm*1e6;
Input.My_Nmm = Input.My_kNm*1e6;
Input.V_N = Input.V_kN*1e3;

%% 3. RUN GENETIC ALGORITHM (GA) WITH "SEEDING" STRATEGY
fprintf('>>> PROBLEM: %s (Mx=%.0f, My=%.0f, V=%.0f)\n', CaseName, Input.M_kNm, Input.My_kNm, Input.V_kN);

% --- CREATE SEED POPULATION ---
% The first 10 individuals must be I-Beams (sep=0) to "prime" the AI
InitialPop = zeros(50, 5); 
for i = 1:50
    InitialPop(i, 1:4) = lb(1:4) + (ub(1:4) - lb(1:4)) .* rand(1,4);
    if i <= 10 
        InitialPop(i, 5) = 0;   % SEED GENE: I-Beam
    else
        InitialPop(i, 5) = lb(5) + (ub(5) - lb(5)) * rand; 
    end
end

options = optimoptions('ga', ...
    'PopulationSize', 20, ...    
    'MaxGenerations', 10, ...    
    'Display', 'iter', ...
    'PlotFcn', @gaplotbestf, ...
    'InitialPopulationMatrix', InitialPop); 

fprintf('>>> AI IS THINKING ...\n');
tic;
Objective = @(x) ObjectiveFunction_GA_Morph(x, Input);
[x_best, fval] = ga(Objective, nvars, [], [], [], [], lb, ub, [], options);
RunTime = toc;

%% 4. ANALYSIS & PLOTTING
h=x_best(1); b=x_best(2); tf=x_best(3); tw=x_best(4); sep=x_best(5);

% --- [IMPORTANT] SNAP TO ZERO ---
% If sep is small (GA didn't reach exactly 0), force it to 0 for correct plotting
if sep < 25
    sep = 0;
    x_best(5) = 0; % Update for plotting
end

% Recalculate mass
[~, Geom] = calc_normal_stress(generate_morph_section(x_best), [], struct('Mx',0,'My',0,'Nz',0));
Mass_kg = abs(Geom.Area * 1e-6) * Input.L_m * 7850;

% --- SMART NAMING LOGIC (UPDATED) ---
% Classify based on geometric ratios rather than rigid numbers
Gap = sep * 2; 

if sep < 5 % Considered as joined/solid
    % Classify I or H
    if b >= 0.8 * h 
        Type = 'H-Beam (Wide Flange)'; 
    else
        Type = 'I-Beam (Economy)'; 
    end
elseif Gap >= 50 % <--- [IMPORTANT] Lower threshold to 50mm (instead of 300mm)
    % Web separated (2 webs)
    
    % If separated widely to edges (> 60% of width) -> Call it Box
    if Gap > 0.6 * b  
        Type = 'Box Girder (Wide)';
    else
        % If separated moderately (like your 220mm case) -> Call it Composite
        Type = 'Double-Web / Composite'; 
    end
else
    Type = 'Hybrid / Custom';
end

fprintf('\n============================================\n');
fprintf('OPTIMIZATION RESULT: %s\n', CaseName);
fprintf('  * Shape:             %s\n', Type);
fprintf('  * Mass:              %.2f kg (%.1f kg/m)\n', abs(Mass_kg), Mass_kg/Input.L_m);
fprintf('--------------------------------------------\n');
fprintf('  * Height (h):        %.0f mm\n', h);
fprintf('  * Width (b):         %.0f mm\n', b);
fprintf('  * Flange (tf):       %.1f mm\n', tf);
fprintf('  * Web (tw):          %.1f mm\n', tw);
fprintf('  * Web Gap:           %.0f mm\n', sep*2);
fprintf('============================================\n');

% --- 3D VISUALIZATION ---
PolyCoords = generate_morph_section(x_best);
ps = polyshape(PolyCoords(:,1), PolyCoords(:,2));

figure('Name', CaseName, 'Color', 'k', 'Position', [100 100 1000 500]);

% 2D
subplot(1,2,1); plot(ps, 'FaceColor', [1 0.6 0], 'EdgeColor', 'w');
title('CROSS SECTION', 'Color', 'w'); axis equal; grid on; set(gca,'XColor','w','YColor','w','GridAlpha',0.3);

% 3D Extrusion
subplot(1,2,2); z_len = 2500;
TR = triangulation(ps); pts2D = TR.Points; connectivity = TR.ConnectivityList;
pts3D = [pts2D, zeros(size(pts2D,1),1); pts2D, ones(size(pts2D,1),1)*z_len];
faces_front = connectivity; faces_back = connectivity + size(pts2D,1);
boundary_edges = freeBoundary(TR);
faces_side = zeros(size(boundary_edges,1)*2, 3);
for i = 1:size(boundary_edges,1)
    p1=boundary_edges(i,1); p2=boundary_edges(i,2); p1b=p1+size(pts2D,1); p2b=p2+size(pts2D,1);
    faces_side(2*i-1,:)=[p1, p2, p1b]; faces_side(2*i,:)=[p2, p2b, p1b];
end
all_faces = [faces_front; faces_back; faces_side];
trisurf(all_faces, pts3D(:,1), pts3D(:,2), pts3D(:,3), 'FaceColor', [1 0.6 0], 'EdgeColor', 'none');
hold on; trimesh(all_faces, pts3D(:,1), pts3D(:,2), pts3D(:,3), 'FaceColor','none','EdgeColor','k','LineWidth',0.5);
view(30,30); camlight; lighting gouraud; title(['3D VIEW: ', Type], 'Color','w','FontSize',14); axis equal; axis off;