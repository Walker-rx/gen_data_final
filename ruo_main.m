clear;
close all;

t = datetime('now');
save_path = "snr_ser/direct/"+t.Month+"."+t.Day;
if(~exist(save_path,'dir'))
    mkdir(char(save_path));
end
    
channel_choice = 4;
dir_up = "./data_set_final/";
test = [1 0 1 0 1 1 1];
% bias = input('bias(mA): ')

% dp821A = visa('ni','USB0::0x1AB1::0x0E11::DP8E163250125::INSTR');
% % dp821A = visa('ni','ASRL3:INSTR');
% fopen(dp821A);
% % fprintf(dp821A,'*IDN?');
% % aa = fscanf(dp821A);
% % display(aa);
% fprintf(dp821A,':OUTP:OCP:VAL CH2,1.500');
% fprintf(dp821A,':OUTP:OCP:VAL? CH2');
% aa = fscanf(dp821A);
% display(aa);
% fprintf(dp821A,':OUTP:OCP CH2,ON');
% fprintf(dp821A,':OUTP CH2,ON');
% fprintf(dp821A,':APPL CH1,24,1.000');
% fprintf(dp821A,':OUTP CH1,ON');

bias_name = 780;
pause(0.5);

data_length = 10000;
zero_length = 10000;
ls_order = 50;

origin_rate = 25e6; 
bw = origin_rate/2;         % baseband bandwidth
f_rate = 160e6;
d_rate = 150e6;

times = d_rate/origin_rate;
num_of_windows = 100;

% pilot = pilot_gen([0 0 0 1 1 1 1]);
% pilot = pilot_gen([1 1 1 0 0 0 1 1 1]);
pilot = ruo_pilot_gen([1 1 1 1 1 1 0 1 0 1 0 1 1]);
pilot_ps = bandpower(pilot);
pilot_length = length(pilot);
pilot_bpsk = pilot*2-1;

filter_ord = 1000;     % filter order used in function sam_rate_con
rp = 0.00057565;      
rst = 1e-4;       % filter parameter used in function sam_rate_con

llcm_transmit = lcm(origin_rate,f_rate);
upf_transmit = llcm_transmit/origin_rate;  % upsampling parameters
dof_transmit = llcm_transmit/f_rate;
ups_rate_transmit = origin_rate*upf_transmit;
filter_transmit = firceqrip(filter_ord,bw/(ups_rate_transmit/2),[rp rst],'passedge'); % Impulse function
filter_transmit = filter_transmit./norm(filter_transmit,2)*sqrt(bw/ups_rate_transmit*2); % filter used in function sam_rate_con in transmit part

llcm_receive = lcm(f_rate,d_rate);
upf_receive = llcm_receive/f_rate;  % upsampling parameters
dof_receive = llcm_receive/d_rate;
ups_rate_receive = f_rate*upf_receive;
filter_receive = firceqrip(filter_ord,bw/(ups_rate_receive/2),[rp rst],'passedge'); % Impulse function
filter_receive = filter_receive./norm(filter_receive,2)*sqrt(bw/ups_rate_receive*2); % filter used in function sam_rate_con in receive part

% origin_rate = gpuArray(double(origin_rate));
% f_rate = gpuArray(double(f_rate));
% d_rate = gpuArray(double(d_rate));
% num_of_windows = gpuArray(double(num_of_windows));
% times = gpuArray(double(times));
% pilot_length = gpuArray(double(pilot_length));
% delay = gpuArray(double(delay));
% filter_transmit = gpuArray(double(filter_transmit));
% filter_receive = gpuArray(double(filter_receive));
% upf_transmit = gpuArray(double(upf_transmit));
% dof_transmit = gpuArray(double(dof_transmit));
% upf_receive = gpuArray(double(upf_receive));
% dof_receive = gpuArray(double(dof_receive));
% h_channel = gpuArray(double(h_channel));
% h_channel_delay = gpuArray(double(h_channel_delay));

amp_begin = 51;
amp_end = 52;
fprintf('add zero,ls order=%d,pilot length=%d .\n',ls_order,pilot_length);
for amp = amp_begin:amp_end
    looptime = 0;
    ps = 0;
    pn = 0;
    snr_sum = 0;
    errornum_zf = 0;
    errornum_mmse = 0;
    errornum_ls = 0;
    total_length = 0;
    fprintf('amp = %d .\n', amp);
    
    fsnr = fopen(save_path+"/snr.txt",'w');
    fser = fopen(save_path+"/ser.txt",'w');
    fprintf(fsnr,'add zero ,pilot length  = %.8f , ls order  = %.8f \r\n',pilot_length,ls_order);
    fprintf(fser,'add zero ,pilot length  = %.8f , ls order  = %.8f \r\n',pilot_length,ls_order);
    fclose(fsnr);
    fclose(fser);
%     while(errornum_ls <= 30 || looptime < 2000)
    while (1)
%     while(errornum_zf <= 100 || errornum_mmse <= 100 || looptime < 50)
%         if mod(looptime,1000) == 0
%             ruo_zero_send;
%             pn = bandpower(noise);
%         end
  
        looptime = looptime+1;
        
        ruo_pam4_send;
        
        signal_received = ruo_sam_rate_con(signal_pass_channel,filter_receive,upf_receive,dof_receive);

        [fin_syn_point,coar_syn_point] = ruo_signal_syn(origin_rate,d_rate,signal_ori,signal_received,num_of_windows);
        
        signal_downsample = signal_received(fin_syn_point:times:end);
        noise = signal_downsample(pilot_length+100:pilot_length+6000);
        pn_loop = bandpower(noise);
        data_received = signal_downsample(pilot_length+zero_length+1:pilot_length+zero_length+1+data_length-1);
        p = bandpower(data_received);
        ps_loop = p - pn_loop;
        
%         noise = signal_received(fin_syn_point+pilot_length*times+200:fin_syn_point+pilot_length*times+800);
%         pn = bandpower(noise);
%         data_received = signal_received(fin_syn_point+pilot_length*times+zero_length*times:fin_syn_point+pilot_length*times+zero_length*times+data_length*times-1);
%         p = bandpower(data_received);
%         ps = p - pn;
%         snr_loop = 10*log10(ps/pn);
        
        signal_demod_ls = ruo_signal_equal(signal_ori,signal_received,times,coar_syn_point,pilot_length,zero_length,num_of_windows,{'ls',ls_order,pilot_ps,data_mpam_ps});

%         signal_demod_ls = gather(signal_demod_ls);

        data_demod_ls = signal_demod_ls(pilot_length+zero_length+1:end);

        if length(data_demod_ls) < length(data)
            compare_length = length(data_demod_ls);
            total_length = total_length + compare_length;
            errornum_ls_loop = sum(data_demod_ls ~= data(1:compare_length));
            error_location = find(data_demod_ls ~= data(1:compare_length));
        else
            compare_length = length(data);
            total_length = total_length + compare_length;
            errornum_ls_loop = sum(data_demod_ls(1:compare_length) ~= data);
            error_location = find(data_demod_ls(1:compare_length) ~= data);
        end
        
        errornum_ls = errornum_ls+errornum_ls_loop;
        ps = ps + ps_loop;
        pn = pn + pn_loop;
%         snr_sum = snr_sum + snr_loop;
        
        ser_ls = errornum_ls/total_length;
        snr_ls = 10*log10(ps/pn);
%         snr_ls = snr_sum/looptime;
        if mod(looptime,20) == 0
           fprintf(' %f times, amp = %d , data num = %d ,ls error num = %d .\n',looptime,amp,length(data_demod_ls),errornum_ls_loop);
           fprintf(' %f times, snr = %d , total ls error num = %d,ls error rate = %.6g .\n',looptime,snr_ls,errornum_ls,ser_ls);
           disp(["error location = ",error_location]);
%            fprintf(' %f times, snr = %f , zf error num = %f , mmse error num = %f .\n',looptime,snr,errornum_zf,errornum_mmse);
%            fprintf(' %f times, snr = %f , zf error rate = %f , mmse error rate = %f .\n',looptime,snr,ser_zf,ser_mmse);
        end
          
    end
    
%     ser_ls = gather(ser_ls);

    if amp == amp_begin
        fsnr = fopen(save_path+"/snr.txt",'w');
        fser = fopen(save_path+"/ser.txt",'w');
        fprintf(fsnr,'add zero ,pilot length  = %.8f , ls order  = %.8f \r\n',pilot_length,ls_order);
        fprintf(fser,'add zero ,pilot length  = %.8f , ls order  = %.8f \r\n',pilot_length,ls_order);
    else
        fsnr = fopen(save_path+"/snr.txt",'a');
        fser = fopen(save_path+"/ser.txt",'a');
    end
    fprintf(fsnr,'%.8f \r\n',snr_ls);
    fprintf(fser,'%.6g \r\n',ser_ls);
    fclose(fsnr);
    fclose(fser);

end


